import XCTest
@testable import ClaudeSessions

/// Unit tests for the pure logic that the app's correctness and safety rest on.
/// Mirrors web/test/unit.mjs so both platforms' duplicated logic stays in step.
final class CoreTests: XCTestCase {

    // MARK: - Secret redaction (mirrors redactSecrets in server.js)

    func testRedactsVendorKeys() {
        XCTAssertFalse(Redaction.redact("sk-ant-api03-abcdefghij0123456789klmnop").contains("abcdefghij"))
        XCTAssertTrue(Redaction.redact("token ghp_ABCDEFGHIJKLMNOPQRST0123456789").contains("[REDACTED]"))
        XCTAssertTrue(Redaction.redact("AKIAIOSFODNN7EXAMPLE").contains("[REDACTED]"))
        XCTAssertTrue(Redaction.redact("Authorization: Bearer abcdefghijklmnopqrstuvwx").contains("[REDACTED]"))
    }

    func testRedactsAssignmentValueKeepsKey() {
        let out = Redaction.redact("DB_PASSWORD=hunter2secret")
        XCTAssertTrue(out.hasPrefix("DB_PASSWORD="))
        XCTAssertTrue(out.contains("[REDACTED]"))
        XCTAssertFalse(out.contains("hunter2secret"))
    }

    func testLeavesProseAndCodeUntouched() {
        XCTAssertEqual(Redaction.redact("call the search API with a function"),
                       "call the search API with a function")
        XCTAssertEqual(Redaction.redact("edit src/main.ts and run npm test"),
                       "edit src/main.ts and run npm test")
        XCTAssertEqual(Redaction.redact(""), "")
    }

    // MARK: - Pricing (mirrors PRICING / rateFor in server.js)

    func testPricingPrefixMatchAndPrecedence() {
        XCTAssertEqual(Pricing.pricing(for: "claude-fable-5").input, 10.0)
        // Generic opus catches 4-8; specific 4-1 must win over generic opus.
        XCTAssertEqual(Pricing.pricing(for: "claude-opus-4-8").input, 5.0)
        XCTAssertEqual(Pricing.pricing(for: "claude-opus-4-1-20250805").input, 15.0)
        XCTAssertEqual(Pricing.pricing(for: "claude-haiku-4-5-20251001").input, 1.0)
    }

    func testCostArithmetic() {
        // 1M input @ $5/M + 1M output @ $25/M = $30 exactly.
        let c = Pricing.cost(model: "claude-opus-4-8",
                             input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(c, 30.0, accuracy: 0.0001)
    }

    // MARK: - Session id validation + resume script safety

    func testSessionIdValidation() {
        XCTAssertTrue(SessionMeta.isValidSessionId("0f6b3c2a-1111-2222-3333-abcdefabcdef"))
        XCTAssertFalse(SessionMeta.isValidSessionId("x; rm -rf ~"))
        XCTAssertFalse(SessionMeta.isValidSessionId("../../etc/passwd"))
        XCTAssertFalse(SessionMeta.isValidSessionId(""))
    }

    func testResumeScriptNeutralizesInjection() {
        var evil = SessionMeta(sessionId: "0f6b3c2a-1111-2222-3333-abcdefabcdef",
                               transcriptPath: "/dev/null", projectKey: "k")
        evil.cwd = #"/tmp/x";touch /tmp/pwned;#"#
        let script = ResumeService.makeResumeScript(session: evil)
        XCTAssertNotNil(script)
        // The dangerous cwd must be single-quoted; nothing executable escapes.
        XCTAssertTrue(script!.contains("cd '"))
        XCTAssertTrue(script!.contains("exec claude --resume '0f6b3c2a-1111-2222-3333-abcdefabcdef'"))

        // A non-UUID id yields no script at all.
        var bad = SessionMeta(sessionId: "x; rm -rf ~", transcriptPath: "/dev/null", projectKey: "k")
        bad.cwd = "/tmp"
        XCTAssertNil(ResumeService.makeResumeScript(session: bad))
    }

    // MARK: - Handoff merge (pure functions shared by write + diff/copy previews)

    private let section = "## 2026-07-10 — New Work\n**Done**\n- shipped the thing"

    /// Prepending under a leading "# " title keeps the title first, the new section next, and
    /// preserves everything that was below (the older sections).
    func testMergedProgressPrependsUnderTitle() {
        let existing = """
        # Progress — demo

        ## 2026-07-09 — Older Work
        **Done**
        - earlier stuff
        """
        let out = HandoffService.mergedProgress(existing: existing, projectName: "demo", section: section)

        XCTAssertTrue(out.hasPrefix("# Progress — demo\n\n## 2026-07-10 — New Work"),
                      "title stays first, new dated section is inserted directly after it")
        XCTAssertTrue(out.contains("## 2026-07-09 — Older Work"), "old section is preserved")
        XCTAssertTrue(out.contains("- earlier stuff"), "old content is preserved")
        // New section must appear ABOVE the old one.
        let newIdx = out.range(of: "## 2026-07-10")!.lowerBound
        let oldIdx = out.range(of: "## 2026-07-09")!.lowerBound
        XCTAssertTrue(newIdx < oldIdx, "newest section is on top")
        XCTAssertTrue(out.hasSuffix("\n"), "always terminated with a newline")
    }

    /// A missing (nil) file is created fresh with a "# Progress — <name>" title.
    func testMergedProgressFreshFile() {
        let out = HandoffService.mergedProgress(existing: nil, projectName: "demo", section: section)
        XCTAssertEqual(out, "# Progress — demo\n\n## 2026-07-10 — New Work\n**Done**\n- shipped the thing\n")

        // An empty existing file is treated the same as no file.
        XCTAssertEqual(HandoffService.mergedProgress(existing: "", projectName: "demo", section: section), out)
    }

    /// A file with no leading "# " title gets the section prepended at the very top.
    func testMergedProgressPrependsWhenNoTitle() {
        let out = HandoffService.mergedProgress(existing: "just some notes\n", projectName: "demo", section: section)
        XCTAssertTrue(out.hasPrefix("## 2026-07-10 — New Work"))
        XCTAssertTrue(out.contains("just some notes"))
    }

    /// Upserting the managed block into a CLAUDE.md that already has one REPLACES it in place —
    /// it does not duplicate the block, and content outside the markers is untouched.
    func testMergedClaudeReplacesNotDuplicates() {
        let firstBlock = HandoffService.markerBlock(content: "old durable knowledge")
        let existing = "# My CLAUDE.md\n\nHand-written notes.\n\n\(firstBlock)\n"

        let newBlock = HandoffService.markerBlock(content: "new durable knowledge")
        let out = HandoffService.mergedClaude(existing: existing, block: newBlock)

        XCTAssertEqual(out.components(separatedBy: HandoffService.claudeStartMarker).count, 2,
                       "exactly one start marker (block replaced, not duplicated)")
        XCTAssertEqual(out.components(separatedBy: HandoffService.claudeEndMarker).count, 2,
                       "exactly one end marker")
        XCTAssertTrue(out.contains("new durable knowledge"), "block content updated")
        XCTAssertFalse(out.contains("old durable knowledge"), "old block content is gone")
        XCTAssertTrue(out.contains("Hand-written notes."), "user content outside markers is preserved")
    }

    /// Creating (nil existing) yields the block only; appending to an unmarked file keeps the
    /// user's text and adds the block after it.
    func testMergedClaudeCreateAndAppend() {
        let block = HandoffService.markerBlock(content: "durable")

        let created = HandoffService.mergedClaude(existing: nil, block: block)
        XCTAssertEqual(created, block + "\n")

        let appended = HandoffService.mergedClaude(existing: "user notes", block: block)
        XCTAssertTrue(appended.hasPrefix("user notes"), "existing content stays on top")
        XCTAssertTrue(appended.contains(block), "block is appended")
        XCTAssertTrue(appended.hasSuffix("\n"))
    }

    // MARK: - Unified line diff

    /// A pure insertion (new dated section prepended under a kept title) shows exactly the new
    /// lines as `.added`, with the surrounding unchanged lines as `.context`.
    func testUnifiedDiffPureInsertion() {
        let old = "# Progress — demo\n\n## 2026-07-09 — Older\n- earlier\n"
        let new = HandoffService.mergedProgress(existing: old, projectName: "demo", section: section)
        let diff = HandoffService.unifiedDiff(old: old, new: new)

        // No removals — this is an insertion only.
        XCTAssertFalse(diff.contains { $0.kind == .removed }, "nothing is removed on a pure insertion")

        let added = diff.filter { $0.kind == .added }.map(\.text)
        XCTAssertTrue(added.contains("## 2026-07-10 — New Work"), "the new heading is added")
        XCTAssertTrue(added.contains("- shipped the thing"), "the new body line is added")

        let context = diff.filter { $0.kind == .context }.map(\.text)
        XCTAssertTrue(context.contains("# Progress — demo"), "the kept title is context")
        XCTAssertTrue(context.contains("## 2026-07-09 — Older"), "the preserved old section is context")

        // Concatenating context+added in order must reconstruct the new file's lines exactly.
        let rebuilt = diff.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n") + "\n"
        XCTAssertEqual(rebuilt, new, "diff faithfully represents the merged result")
    }

    /// A brand-new file diffs as every line added.
    func testUnifiedDiffNewFileIsAllAdded() {
        let new = "line one\nline two\nline three\n"
        let diff = HandoffService.unifiedDiff(old: "", new: new)
        XCTAssertEqual(diff.count, 3)
        XCTAssertTrue(diff.allSatisfy { $0.kind == .added })
        XCTAssertEqual(diff.map(\.text), ["line one", "line two", "line three"])
    }

    /// The copy buttons copy EXACTLY what the writer would produce — assert the merged strings
    /// are the single source of truth (this is what "Copy PROGRESS.md/CLAUDE.md" put on the pasteboard).
    func testMergedContentMatchesWhatCopyProduces() {
        // PROGRESS.md fresh-file copy target.
        let progressCopy = HandoffService.mergedProgress(existing: nil, projectName: "demo", section: section)
        XCTAssertEqual(progressCopy, "# Progress — demo\n\n\(section)\n")

        // CLAUDE.md fresh-file copy target is the marker block only.
        let claudeCopy = HandoffService.mergedClaude(
            existing: nil, block: HandoffService.markerBlock(content: "durable notes"))
        XCTAssertTrue(claudeCopy.hasPrefix(HandoffService.claudeStartMarker))
        XCTAssertTrue(claudeCopy.contains("durable notes"))
        XCTAssertTrue(claudeCopy.contains(HandoffService.claudeEndMarker))
    }
}
