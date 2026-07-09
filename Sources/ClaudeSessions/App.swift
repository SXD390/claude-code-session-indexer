import AppKit
import SwiftUI

@main
struct ClaudeSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = SessionStore()
    /// Opt-in fast-search toggle (default OFF). Read by `SearchIndex.isEnabled`; when off,
    /// deep search behaves byte-identically to before and no index.db is ever created.
    @AppStorage("csiSearchIndexEnabled") private var searchIndexEnabled = false

    init() {
        // Headless smoke test: `ClaudeSessions --scan-test` parses everything and exits.
        if CommandLine.arguments.contains("--scan-test") {
            Self.runScanTest()
        }
        // Headless summary test: `ClaudeSessions --summary-test <sessionId>`
        if let idx = CommandLine.arguments.firstIndex(of: "--summary-test"),
           CommandLine.arguments.count > idx + 1 {
            Self.runSummaryTest(sessionId: CommandLine.arguments[idx + 1])
        }
        // Headless usage test: `ClaudeSessions --usage-test` sanity-checks the analytics engine.
        if CommandLine.arguments.contains("--usage-test") {
            Self.runUsageTest()
        }
        // Headless brief test: `ClaudeSessions --brief-test <sessionId>`
        if let idx = CommandLine.arguments.firstIndex(of: "--brief-test"),
           CommandLine.arguments.count > idx + 1 {
            Self.runBriefTest(sessionId: CommandLine.arguments[idx + 1])
        }
        // Headless handoff test: `ClaudeSessions --handoff-test <sessionId>` — generates and
        // prints the three sections (does NOT write files into any project directory).
        if let idx = CommandLine.arguments.firstIndex(of: "--handoff-test"),
           CommandLine.arguments.count > idx + 1 {
            Self.runHandoffTest(sessionId: CommandLine.arguments[idx + 1])
        }
        // Headless write test: `ClaudeSessions --handoff-write-test <dir>` — unit-drives the
        // file-writing logic against a throwaway directory (no `claude -p`, no real project).
        if let idx = CommandLine.arguments.firstIndex(of: "--handoff-write-test"),
           CommandLine.arguments.count > idx + 1 {
            Self.runHandoffWriteTest(dir: CommandLine.arguments[idx + 1])
        }
        // Headless search parity test: `ClaudeSessions --search-test <query>` runs the same
        // query through BOTH the concurrent scan and the FTS5 index and compares the results.
        if let idx = CommandLine.arguments.firstIndex(of: "--search-test"),
           CommandLine.arguments.count > idx + 1 {
            Self.runSearchTest(query: CommandLine.arguments[idx + 1])
        }
        // Security regression harness — env-gated so it never runs in normal use:
        //   CSI_SECURITY_SELFTEST=1 ClaudeSessions --security-selftest <throwaway-dir>
        // Exercises the .command generation and handoff writes against an ADVERSARIAL fixture
        // (shell metacharacters in cwd/title, non-UUID ids, injected CLAUDE.md markers) and
        // asserts injection is neutralized. Never opens a .command; never writes a real project.
        if CommandLine.arguments.contains("--security-selftest"),
           ProcessInfo.processInfo.environment["CSI_SECURITY_SELFTEST"] == "1",
           let idx = CommandLine.arguments.firstIndex(of: "--security-selftest"),
           CommandLine.arguments.count > idx + 1 {
            Self.runSecuritySelfTest(dir: CommandLine.arguments[idx + 1])
        }
    }

    /// Adversarial self-test for the exec/write surfaces. Exits 0 only if every assertion holds.
    private static func runSecuritySelfTest(dir: String) {
        var failures: [String] = []
        func check(_ cond: Bool, _ label: String) {
            print(cond ? "  PASS  \(label)" : "  FAIL  \(label)")
            if !cond { failures.append(label) }
        }

        // Metacharacter payloads an attacker could plant in a transcript's cwd / title.
        let evilCwd = #"/tmp/x";calc;#$(touch /tmp/pwned)`id`"# + "\nrm -rf ~"
        let evilTitle = "../../etc/pwn; rm -rf ~ $(whoami) `id`"
        let validUUID = "0f6b3c2a-1111-2222-3333-abcdefabcdef"

        print("── ResumeService.makeResumeScript (valid UUID, evil cwd + title) ──")
        var evil = SessionMeta(sessionId: validUUID, transcriptPath: "/dev/null", projectKey: "k")
        evil.cwd = evilCwd
        evil.customTitle = evilTitle
        let script = ResumeService.makeResumeScript(session: evil)
        check(script != nil, "valid UUID produces a script")
        if let s = script {
            print(s)
            // The cwd must appear ONLY inside a single-quoted run: the whole payload is quoted,
            // so the only ' characters are the delimiters we added via '\'' escaping.
            check(s.contains("cd '"), "cwd is single-quoted")
            check(s.contains("exec claude --resume '\(validUUID)'"), "id is single-quoted & flag-free")
            // No metacharacter may sit OUTSIDE quotes. We verify by reconstructing what the shell
            // would see: strip every single-quoted span; nothing dangerous may remain.
            let outsideQuotes = strippingSingleQuotedSpans(s)
            check(!outsideQuotes.contains("$("), "no command substitution outside quotes")
            check(!outsideQuotes.contains("`"), "no backticks outside quotes")
            check(!outsideQuotes.contains("rm -rf"), "no bare rm outside quotes")
            check(!outsideQuotes.contains(";"), "no statement separator outside quotes")
        }

        print("── ResumeService rejects a non-UUID id (would-be injection) ──")
        var bad = SessionMeta(sessionId: "x; rm -rf ~ --dangerously-skip-permissions",
                              transcriptPath: "/dev/null", projectKey: "k")
        bad.cwd = "/tmp"
        check(ResumeService.makeResumeScript(session: bad) == nil, "non-UUID id refused (nil script)")
        check(SessionMeta.isValidSessionId(validUUID), "isValidSessionId accepts a UUID")
        check(!SessionMeta.isValidSessionId("not-a-uuid"), "isValidSessionId rejects non-UUID")

        print("── resumeCommand (clipboard string) quoting ──")
        let rc = evil.resumeCommand
        print("  \(rc)")
        check(rc.contains("cd '"), "resumeCommand single-quotes cwd")
        check(!strippingSingleQuotedSpans(rc).contains("$("), "resumeCommand: no substitution outside quotes")

        print("── HandoffService.writeToProject bounds (evil / traversal / relative cwd) ──")
        let root = URL(fileURLWithPath: dir)
        // (a) writes are refused when cwd does not exist
        var gone = SessionMeta(sessionId: validUUID, transcriptPath: "/dev/null", projectKey: "k")
        gone.cwd = root.appendingPathComponent("does-not-exist-\(UUID().uuidString)").path
        check((try? HandoffService.writeToProject(.init(session: gone, progressSection: "x",
              claudeContent: nil, includeClaudeMd: false))) == nil, "missing cwd → write refused")
        // (b) relative cwd is refused (never resolved against the process working dir)
        var rel = SessionMeta(sessionId: validUUID, transcriptPath: "/dev/null", projectKey: "k")
        rel.cwd = "relative/evil"
        check((try? HandoffService.writeToProject(.init(session: rel, progressSection: "x",
              claudeContent: nil, includeClaudeMd: false))) == nil, "relative cwd → write refused")
        // (c) a real dir whose PATH contains metacharacters is fine — only PROGRESS.md/CLAUDE.md
        //     are ever created inside it, and the metacharacters never reach a shell.
        let weird = root.appendingPathComponent("weird ;$(x)` dir")
        try? FileManager.default.createDirectory(at: weird, withIntermediateDirectories: true)
        var ok = SessionMeta(sessionId: validUUID, transcriptPath: "/dev/null", projectKey: "proj")
        ok.cwd = weird.path
        let written = (try? HandoffService.writeToProject(.init(session: ok,
              progressSection: "## 2026-07-10 — t\n**Done**\n- ok", claudeContent: "durable",
              includeClaudeMd: true))) ?? []
        let names = Set(written.map { $0.lastPathComponent })
        check(written.count == 2 && names == ["PROGRESS.md", "CLAUDE.md"],
              "only PROGRESS.md/CLAUDE.md written, inside cwd")
        check(written.allSatisfy { $0.deletingLastPathComponent().path == weird.path },
              "no path escaped the target directory")

        print("── CLAUDE.md marker-injection can't corrupt the managed block ──")
        let injected = "durable\n\(HandoffService.claudeEndMarker)\nEVIL-APPENDED\n\(HandoffService.claudeStartMarker)"
        let block = HandoffService.markerBlock(content: injected)
        // Exactly one start and one end marker survive.
        check(block.components(separatedBy: HandoffService.claudeStartMarker).count == 2, "exactly one start marker")
        check(block.components(separatedBy: HandoffService.claudeEndMarker).count == 2, "exactly one end marker")

        print(failures.isEmpty ? "\nSECURITY SELF-TEST: ALL PASS" : "\nSECURITY SELF-TEST: \(failures.count) FAILURE(S)")
        exit(failures.isEmpty ? 0 : 1)
    }

    /// Removes every `'...'` single-quoted span from a shell line, leaving only what the shell
    /// would interpret OUTSIDE quotes. Used by the self-test to prove no metacharacter escapes.
    private static func strippingSingleQuotedSpans(_ s: String) -> String {
        var out = ""
        var insideQuote = false
        for ch in s {
            if ch == "'" { insideQuote.toggle(); continue }
            if !insideQuote { out.append(ch) }
        }
        return out
    }

    /// Correctness demo: runs `query` through the concurrent scan and the FTS5 index and prints
    /// whether they agree. Uses a throwaway DB so it never touches the app's real index.db.
    private static func runSearchTest(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { print("query must be ≥ 3 chars"); exit(1) }

        let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: [])
        let metas = listing.map {
            TranscriptScanner.parseTranscript(url: $0.url, projectKey: $0.projectKey, mtime: $0.mtime, size: $0.size)
        }
        let targets = metas.filter { !$0.isEmpty }
            .sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
        let metaById = Dictionary(uniqueKeysWithValues: targets.map { ($0.sessionId, $0) })
        let ordered = targets.map { $0.sessionId }

        // 1) The default concurrent scan.
        var scanById: [String: [RawDeepMatch]] = [:]
        for m in targets {
            scanById[m.sessionId] = TranscriptScanner.deepSearch(
                url: URL(fileURLWithPath: m.transcriptPath), query: q)
        }
        let scanHits = SessionStore.assembleHits(byId: scanById, ordered: ordered, metaById: metaById)

        // 2) The FTS5 index (throwaway DB).
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("csi-search-test-\(UUID().uuidString).db")
        let idxTargets = targets.map {
            SearchIndex.Target(sessionId: $0.sessionId, projectKey: $0.projectKey,
                               transcriptPath: $0.transcriptPath,
                               mtime: $0.fileModifiedAt ?? .distantPast, size: $0.fileSize)
        }
        guard let index = SearchIndex(dbURL: dbURL) else { print("FTS5 unavailable"); exit(1) }
        let t0 = Date()
        index.ensureIndex(targets: idxTargets)
        let buildElapsed = Date().timeIntervalSince(t0)
        let t1 = Date()
        guard let ftsById = index.search(query: q) else { print("index search failed"); exit(1) }
        let ftsElapsed = Date().timeIntervalSince(t1)
        let ftsHits = SessionStore.assembleHits(byId: ftsById, ordered: ordered, metaById: metaById)

        let scanSessions = Set(scanHits.map(\.sessionId))
        let ftsSessions = Set(ftsHits.map(\.sessionId))

        print("query: “\(q)”  over \(targets.count) sessions")
        print("scan : \(scanHits.count) hits in \(scanSessions.count) sessions")
        print("fts  : \(ftsHits.count) hits in \(ftsSessions.count) sessions  (index build \(String(format: "%.3f", buildElapsed))s, query \(String(format: "%.4f", ftsElapsed))s)")
        if scanSessions == ftsSessions {
            print("SESSION SETS MATCH ✓")
        } else {
            print("SESSION SETS DIFFER — scan-only: \(scanSessions.subtracting(ftsSessions)) · fts-only: \(ftsSessions.subtracting(scanSessions))")
        }
        for h in ftsHits.prefix(6) {
            print("  • [\(h.projectName)] \(h.sessionTitle) (\(h.role)): \(h.snippet)")
        }
        try? FileManager.default.removeItem(at: dbURL)
        exit(scanSessions == ftsSessions ? 0 : 1)
    }

    private static func runUsageTest() {
        let start = Date()
        let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: [])
        var records: [UsageRecord] = []
        for entry in listing {
            let extraction = TranscriptScanner.extractUsage(url: entry.url)
            let sessionId = entry.url.deletingPathExtension().lastPathComponent
            records.append(UsageAnalytics.buildRecord(
                sessionId: sessionId, transcriptPath: entry.url.path, projectKey: entry.projectKey,
                mtime: entry.mtime, size: entry.size, extraction: extraction))
        }
        let agg = UsageAnalytics.aggregate(records: records, range: nil, projectNames: [:])
        let elapsed = Date().timeIntervalSince(start)
        print("Scanned \(records.count) transcripts in \(String(format: "%.2f", elapsed))s")
        print("Total est. cost (API-equiv): \(Fmt.cost(agg.totalCost))")
        print("Total active time: \(Fmt.duration(agg.totalActiveSeconds)) (\(String(format: "%.1f", agg.totalActiveSeconds/3600))h)")
        print("Tokens — in: \(Fmt.tokens(agg.totalInput)), out: \(Fmt.tokens(agg.totalOutput)), cacheRead: \(Fmt.tokens(agg.totalCacheRead)), cacheWrite: \(Fmt.tokens(agg.totalCacheWrite))")
        print("Cache hit rate: \(String(format: "%.1f%%", agg.cacheHitRate*100)) — savings \(Fmt.cost(agg.cacheSavings))")
        print("Cost/active-hour: \(Fmt.cost(agg.costPerActiveHour))")
        print("Sessions active: \(agg.sessionsActive) · days: \(agg.days.count) · models: \(agg.models.count)")
        print("Top models by cost:")
        for m in agg.models.prefix(6) {
            print("  \(m.displayName): \(Fmt.cost(m.cost))  [\(m.messageCount) msgs, \(Fmt.tokens(m.totalTokens)) tok]")
        }
        exit(0)
    }

    private static func runBriefTest(sessionId: String) {
        let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: [])
        guard let entry = listing.first(where: { $0.url.lastPathComponent.hasPrefix(sessionId) }) else {
            print("session not found: \(sessionId)"); exit(1)
        }
        let meta = TranscriptScanner.parseTranscript(
            url: entry.url, projectKey: entry.projectKey, mtime: entry.mtime, size: entry.size)
        print("Briefing \(meta.displayTitle)…")
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            let result = await BriefService.generate(session: meta)
            switch result {
            case .success(let b):
                print("STATE:\n\(b.state)\n\nOPEN:\n\(b.open.map { "- \($0)" }.joined(separator: "\n"))\n\nNEXT PROMPT:\n\(b.nextPrompt)")
                // Persist into briefs.json so the app renders it (end-to-end verification).
                let stored = StoredBrief(state: b.state, open: b.open, nextPrompt: b.nextPrompt,
                                         generatedAt: Date(), sessionLastActivity: meta.lastActivityAt, raw: b.raw)
                let url = SessionStore.appSupportDir.appendingPathComponent("briefs.json")
                var map: [String: StoredBrief] = [:]
                if let data = try? Data(contentsOf: url),
                   let existing = try? JSONDecoder().decode([String: StoredBrief].self, from: data) {
                    map = existing
                }
                map[meta.sessionId] = stored
                if let data = try? JSONEncoder().encode(map) {
                    try? data.write(to: url, options: .atomic)
                    print("\n[persisted to briefs.json]")
                }
            case .failure(let err):
                print("ERROR: \(err.localizedDescription)")
            }
            sema.signal()
        }
        sema.wait()
        exit(0)
    }

    private static func runHandoffTest(sessionId: String) {
        let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: [])
        guard let entry = listing.first(where: { $0.url.lastPathComponent.hasPrefix(sessionId) }) else {
            print("session not found: \(sessionId)"); exit(1)
        }
        let meta = TranscriptScanner.parseTranscript(
            url: entry.url, projectKey: entry.projectKey, mtime: entry.mtime, size: entry.size)
        print("Packaging handoff for \(meta.displayTitle)…  (\(meta.userMessageCount) prompts)")
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            let result = await HandoffService.generate(session: meta)
            switch result {
            case .success(let h):
                print("\n===PROGRESS===\n\(h.progress)")
                print("\n===CLAUDE===\n\(h.claude ?? "NONE")")
                print("\n===KICKSTART===\n\(h.kickstart)")
                print("\n===END===")
                // Persist into handoffs.json so the app can render it (end-to-end verification).
                // This is the app-support cache only — NO files are written into any project dir.
                let stored = StoredHandoff(
                    progress: h.progress, claude: h.claude, kickstart: h.kickstart,
                    generatedAt: Date(), sessionLastActivity: meta.lastActivityAt, raw: h.raw)
                let url = SessionStore.appSupportDir.appendingPathComponent("handoffs.json")
                var map: [String: StoredHandoff] = [:]
                if let data = try? Data(contentsOf: url),
                   let existing = try? JSONDecoder().decode([String: StoredHandoff].self, from: data) {
                    map = existing
                }
                map[meta.sessionId] = stored
                if let data = try? JSONEncoder().encode(map) {
                    try? data.write(to: url, options: .atomic)
                    print("\n[persisted to handoffs.json — no project files written]")
                }
            case .failure(let err):
                print("ERROR: \(err.localizedDescription)")
            }
            sema.signal()
        }
        sema.wait()
        exit(0)
    }

    /// Exercises the file-writing logic (prepend / append / marker-replace) against a
    /// throwaway directory, WITHOUT running `claude -p` or touching any real project.
    private static func runHandoffWriteTest(dir: String) {
        let cwd = URL(fileURLWithPath: dir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDir), isDir.boolValue else {
            print("dir not found: \(dir)"); exit(1)
        }
        // A synthetic session whose cwd is the throwaway dir.
        var meta = SessionMeta(sessionId: "write-test", transcriptPath: "/dev/null", projectKey: "test")
        meta.cwd = cwd.path

        func dump(_ label: String) {
            print("\n──────── \(label) ────────")
            for name in ["PROGRESS.md", "CLAUDE.md"] {
                let u = cwd.appendingPathComponent(name)
                let body = (try? String(contentsOf: u, encoding: .utf8)) ?? "<missing>"
                print("=== \(name) ===\n\(body)")
            }
        }

        let sectionA = """
        ## 2026-07-10 — First Handoff
        **Done**
        - Implemented the Handoff feature
        **Open threads**
        - Wire up the context menu
        **How to verify**
        - swift build
        """
        let sectionB = """
        ## 2026-07-11 — Second Handoff
        **Done**
        - Added the write-path test
        **Open threads**
        - none
        **How to verify**
        - .build/debug/ClaudeSessions --handoff-write-test /tmp/handoff-write-test
        """
        let claudeA = "## Build\n- `swift build`\n## Test\n- `.build/debug/ClaudeSessions --scan-test`"
        let claudeB = "## Build\n- `swift build -c release`\n## Notes\n- Only writes inside session.cwd"

        do {
            print("Write test in: \(cwd.path)")
            dump("INITIAL (fixtures)")

            _ = try HandoffService.writeToProject(HandoffService.WriteRequest(
                session: meta, progressSection: sectionA, claudeContent: claudeA, includeClaudeMd: true))
            dump("AFTER WRITE #1 (prepend into existing PROGRESS, append/replace into CLAUDE)")

            let written = try HandoffService.writeToProject(HandoffService.WriteRequest(
                session: meta, progressSection: sectionB, claudeContent: claudeB, includeClaudeMd: true))
            dump("AFTER WRITE #2 (newest section on top, CLAUDE block replaced not duplicated)")

            print("\nwrote: \(written.map { $0.lastPathComponent }.joined(separator: ", "))")
        } catch {
            print("WRITE ERROR: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }

    private static func runSummaryTest(sessionId: String) {
        let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: [])
        guard let entry = listing.first(where: { $0.url.lastPathComponent.hasPrefix(sessionId) }) else {
            print("session not found: \(sessionId)")
            exit(1)
        }
        let meta = TranscriptScanner.parseTranscript(
            url: entry.url, projectKey: entry.projectKey, mtime: entry.mtime, size: entry.size)
        print("Summarizing \(meta.displayTitle)…")
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            let result = await SummaryService.summarize(session: meta)
            switch result {
            case .success(let text): print("SUMMARY:\n\(text)")
            case .failure(let err): print("ERROR: \(err.localizedDescription)")
            }
            sema.signal()
        }
        sema.wait()
        exit(0)
    }

    private static func runScanTest() {
        let start = Date()
        let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: [])
        var metas: [SessionMeta] = []
        for entry in listing {
            metas.append(TranscriptScanner.parseTranscript(
                url: entry.url, projectKey: entry.projectKey, mtime: entry.mtime, size: entry.size))
        }
        let elapsed = Date().timeIntervalSince(start)
        let named = metas.filter(\.hasCustomName).count
        let ai = metas.filter { $0.aiTitle != nil }.count
        let withPrompt = metas.filter { $0.firstPrompt != nil }.count
        let withCwd = metas.filter { $0.cwd != nil }.count
        let active = TranscriptScanner.activeSessions()
        print("Parsed \(metas.count) transcripts in \(String(format: "%.2f", elapsed))s")
        print("named=\(named) aiTitled=\(ai) firstPrompt=\(withPrompt) cwd=\(withCwd) active=\(active.count)")
        for meta in metas.sorted(by: { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }).prefix(8) {
            let date = meta.lastActivityAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "?"
            print("• [\(meta.projectDisplayName)] \(meta.displayTitle)  (\(meta.userMessageCount) prompts, \(date))")
            print("    \(meta.resumeCommand)")
        }
        exit(0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Sessions") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Toggle("Fast Search Index (FTS5)", isOn: $searchIndexEnabled)
                    .help("Build a local SQLite full-text index so deep search is instant across thousands of sessions. Off by default.")
            }
        }
    }
}

/// Makes the app behave as a regular windowed app even when the binary is
/// launched outside a bundle (e.g. `swift run` during development).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
