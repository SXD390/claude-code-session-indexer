import AppKit
import SwiftUI

@main
struct ClaudeSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = SessionStore()

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
