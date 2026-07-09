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
        .defaultSize(width: 1180, height: 740)
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
