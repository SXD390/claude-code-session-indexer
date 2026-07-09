import Foundation
import SwiftUI

/// Loads, caches, and refreshes session metadata for the whole UI.
@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [SessionMeta] = []
    @Published var activeBySessionId: [String: ActiveSession] = [:]
    @Published var summaries: [String: StoredSummary] = [:]
    @Published var isLoading = false
    @Published var lastRefreshed: Date?
    @Published var generatingSummaryFor: Set<String> = []
    @Published var summaryErrors: [String: String] = [:]

    nonisolated static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metaCacheURL: URL { Self.appSupportDir.appendingPathComponent("meta-cache.json") }
    private var summariesURL: URL { Self.appSupportDir.appendingPathComponent("summaries.json") }

    /// Summary generation runs `claude -p` with this cwd; its own transcripts land in a
    /// project dir we exclude from scans so the app never lists its own summary runs.
    nonisolated static var summaryWorkDir: URL {
        let dir = appSupportDir.appendingPathComponent("summary-runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static var excludedProjectKeys: Set<String> {
        // ~/.claude/projects encodes the cwd path with non-alphanumerics replaced by "-".
        let encoded = summaryWorkDir.path.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return [String(encoded)]
    }

    init() {
        loadSummaries()
    }

    // MARK: - Refresh

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let cached = loadMetaCache()

        Task.detached(priority: .userInitiated) {
            let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: Self.excludedProjectKeys)
            var fresh: [SessionMeta] = []
            var toParse: [(URL, String, Date, Int64)] = []

            for entry in listing {
                if let hit = cached[entry.url.path],
                   hit.fileModifiedAt == entry.mtime, hit.fileSize == entry.size {
                    fresh.append(hit)
                } else {
                    toParse.append(entry)
                }
            }

            // Parse changed/new transcripts concurrently, bounded by core count.
            let parsed = await withTaskGroup(of: SessionMeta.self, returning: [SessionMeta].self) { group in
                let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
                var results: [SessionMeta] = []
                var iterator = toParse.makeIterator()
                var inFlight = 0

                func addNext(_ group: inout TaskGroup<SessionMeta>) -> Bool {
                    guard let (url, key, mtime, size) = iterator.next() else { return false }
                    group.addTask {
                        TranscriptScanner.parseTranscript(url: url, projectKey: key, mtime: mtime, size: size)
                    }
                    return true
                }

                while inFlight < maxConcurrent, addNext(&group) { inFlight += 1 }
                for await meta in group {
                    results.append(meta)
                    if addNext(&group) { inFlight += 1 }
                }
                return results
            }

            fresh.append(contentsOf: parsed)
            let active = TranscriptScanner.activeSessions()
            // Backstop: never surface the app's own `claude -p` summary runs, even if the
            // encoded-project-key exclusion misses them. These always live in a
            // ".../Application Support/<app>/summary-runs" working directory; match any such
            // path so legacy app-support name variants are covered too.
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? ""
            let visible = fresh.filter { meta in
                guard let cwd = meta.cwd else { return true }
                let isSummaryRun = cwd.hasSuffix("/summary-runs")
                    && !appSupport.isEmpty && cwd.hasPrefix(appSupport)
                return !isSummaryRun
            }
            let sorted = visible.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }

            await MainActor.run {
                self.sessions = sorted
                self.activeBySessionId = active
                self.isLoading = false
                self.lastRefreshed = Date()
                self.saveMetaCache(sorted)
            }
        }
    }

    /// Cheap poll: only re-checks which sessions are currently running.
    func refreshActive() {
        Task.detached {
            let active = TranscriptScanner.activeSessions()
            await MainActor.run { self.activeBySessionId = active }
        }
    }

    // MARK: - Derived data

    var projects: [ProjectGroup] {
        var byKey: [String: [SessionMeta]] = [:]
        for s in sessions { byKey[s.projectKey, default: []].append(s) }
        return byKey.map { key, sessions in
            let best = sessions.first { $0.cwd != nil } ?? sessions[0]
            return ProjectGroup(
                key: key,
                displayName: best.projectDisplayName,
                path: best.cwd,
                sessionCount: sessions.count
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var namedCount: Int { sessions.filter(\.hasCustomName).count }
    var activeCount: Int { sessions.filter { activeBySessionId[$0.sessionId] != nil }.count }

    /// Total user prompts across every session (used by the overview dashboard).
    var totalPromptCount: Int { sessions.reduce(0) { $0 + $1.userMessageCount } }

    /// Projects ranked by session count, most first.
    func topProjects(_ limit: Int) -> [ProjectGroup] {
        Array(projects.sorted { $0.sessionCount > $1.sessionCount }.prefix(limit))
    }

    /// Most-recently-active non-empty sessions (sessions is stored newest-first).
    func recentSessions(_ limit: Int) -> [SessionMeta] {
        Array(sessions.filter { !$0.isEmpty }.prefix(limit))
    }

    func filteredSessions(for item: SidebarItem, search: String, sort: SortOrder, hideEmpty: Bool) -> [SessionMeta] {
        var list = sessions
        switch item {
        case .all: break
        case .named: list = list.filter(\.hasCustomName)
        case .active: list = list.filter { activeBySessionId[$0.sessionId] != nil }
        case .project(let key): list = list.filter { $0.projectKey == key }
        }
        if hideEmpty {
            list = list.filter { !$0.isEmpty }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { s in
                s.displayTitle.lowercased().contains(q)
                || (s.customTitle?.lowercased().contains(q) ?? false)
                || (s.aiTitle?.lowercased().contains(q) ?? false)
                || (s.firstPrompt?.lowercased().contains(q) ?? false)
                || s.projectDisplayName.lowercased().contains(q)
                || s.sessionId.lowercased().hasPrefix(q)
                || (summaries[s.sessionId]?.text.lowercased().contains(q) ?? false)
            }
        }
        switch sort {
        case .lastActivity:
            list.sort { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
        case .created:
            list.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .messages:
            list.sort { $0.userMessageCount > $1.userMessageCount }
        }
        return list
    }

    // MARK: - AI summaries

    func generateSummary(for session: SessionMeta) {
        guard !generatingSummaryFor.contains(session.sessionId) else { return }
        generatingSummaryFor.insert(session.sessionId)
        summaryErrors[session.sessionId] = nil

        Task.detached(priority: .utility) {
            let result = await SummaryService.summarize(session: session)
            await MainActor.run {
                self.generatingSummaryFor.remove(session.sessionId)
                switch result {
                case .success(let text):
                    self.summaries[session.sessionId] = StoredSummary(
                        text: text, generatedAt: Date(), sessionLastActivity: session.lastActivityAt
                    )
                    self.saveSummaries()
                case .failure(let err):
                    self.summaryErrors[session.sessionId] = err.localizedDescription
                }
            }
        }
    }

    func summaryIsStale(for session: SessionMeta) -> Bool {
        guard let stored = summaries[session.sessionId] else { return false }
        guard let old = stored.sessionLastActivity, let now = session.lastActivityAt else { return false }
        return now > old.addingTimeInterval(60)
    }

    // MARK: - Persistence

    private func loadMetaCache() -> [String: SessionMeta] {
        guard let data = try? Data(contentsOf: metaCacheURL),
              let list = try? JSONDecoder().decode([SessionMeta].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.transcriptPath, $0) })
    }

    private func saveMetaCache(_ list: [SessionMeta]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: metaCacheURL, options: .atomic)
        }
    }

    private func loadSummaries() {
        if let data = try? Data(contentsOf: summariesURL),
           let map = try? JSONDecoder().decode([String: StoredSummary].self, from: data) {
            summaries = map
        }
    }

    private func saveSummaries() {
        if let data = try? JSONEncoder().encode(summaries) {
            try? data.write(to: summariesURL, options: .atomic)
        }
    }
}
