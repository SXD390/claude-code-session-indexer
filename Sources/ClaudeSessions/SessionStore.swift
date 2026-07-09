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

    // Usage analytics
    @Published var usageRecords: [String: UsageRecord] = [:]   // keyed by transcriptPath
    @Published var usageLoaded = false

    // Pickup Briefs
    @Published var briefs: [String: StoredBrief] = [:]
    @Published var generatingBriefFor: Set<String> = []
    @Published var briefErrors: [String: String] = [:]

    // Handoffs
    @Published var handoffs: [String: StoredHandoff] = [:]
    @Published var generatingHandoffFor: Set<String> = []
    @Published var handoffErrors: [String: String] = [:]

    // Deep search progress
    @Published var deepScanned = 0
    @Published var deepTotal = 0

    nonisolated static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metaCacheURL: URL { Self.appSupportDir.appendingPathComponent("meta-cache.json") }
    private var summariesURL: URL { Self.appSupportDir.appendingPathComponent("summaries.json") }
    private var usageCacheURL: URL { Self.appSupportDir.appendingPathComponent("usage-cache.json") }
    private var briefsURL: URL { Self.appSupportDir.appendingPathComponent("briefs.json") }
    private var handoffsURL: URL { Self.appSupportDir.appendingPathComponent("handoffs.json") }

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
        loadBriefs()
        loadHandoffs()
        loadUsageCache()
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
                self.refreshUsage()
            }
        }
    }

    // MARK: - Usage analytics

    /// Incrementally (re)computes per-session usage records, cached like the meta cache.
    func refreshUsage() {
        let cached = usageRecords
        let excluded = Self.excludedProjectKeys

        Task.detached(priority: .utility) {
            let listing = TranscriptScanner.listTranscripts(excludingProjectPaths: excluded)
            var fresh: [String: UsageRecord] = [:]
            var toParse: [(URL, String, Date, Int64)] = []

            for entry in listing {
                if let hit = cached[entry.url.path],
                   hit.fileModifiedAt == entry.mtime, hit.fileSize == entry.size {
                    fresh[entry.url.path] = hit
                } else {
                    toParse.append((entry.url, entry.projectKey, entry.mtime, entry.size))
                }
            }

            let parsed = await withTaskGroup(of: UsageRecord.self, returning: [UsageRecord].self) { group in
                let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
                var results: [UsageRecord] = []
                var iterator = toParse.makeIterator()
                var inFlight = 0

                func addNext(_ group: inout TaskGroup<UsageRecord>) -> Bool {
                    guard let (url, key, mtime, size) = iterator.next() else { return false }
                    group.addTask {
                        let extraction = TranscriptScanner.extractUsage(url: url)
                        let sessionId = url.deletingPathExtension().lastPathComponent
                        return UsageAnalytics.buildRecord(
                            sessionId: sessionId, transcriptPath: url.path, projectKey: key,
                            mtime: mtime, size: size, extraction: extraction)
                    }
                    return true
                }

                while inFlight < maxConcurrent, addNext(&group) { inFlight += 1 }
                for await rec in group {
                    results.append(rec)
                    if addNext(&group) { inFlight += 1 }
                }
                return results
            }

            for rec in parsed { fresh[rec.transcriptPath] = rec }
            let snapshot = fresh

            await MainActor.run {
                self.usageRecords = snapshot
                self.usageLoaded = true
                self.saveUsageCache(Array(snapshot.values))
            }
        }
    }

    var projectNames: [String: String] {
        var map: [String: String] = [:]
        for p in projects { map[p.key] = p.displayName }
        return map
    }

    /// Aggregated dashboard data for the given range (nil = all time).
    func usageAggregation(range: DateInterval?) -> UsageAggregation {
        UsageAnalytics.aggregate(records: Array(usageRecords.values), range: range, projectNames: projectNames)
    }

    func usageRecord(for session: SessionMeta) -> UsageRecord? {
        usageRecords[session.transcriptPath]
    }

    func session(forId id: String) -> SessionMeta? {
        sessions.first { $0.sessionId == id }
    }

    /// Resolves a preset (+ optional custom dates) into a concrete date interval.
    func dateInterval(preset: RangePreset, customStart: Date, customEnd: Date) -> DateInterval? {
        let cal = Calendar.current
        switch preset {
        case .all:
            return nil
        case .custom:
            let start = cal.startOfDay(for: customStart)
            let end = cal.startOfDay(for: customEnd).addingTimeInterval(86_400 - 1)
            return DateInterval(start: min(start, end), end: max(start, end))
        default:
            guard let days = preset.days else { return nil }
            let todayStart = cal.startOfDay(for: Date())
            let start = cal.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
            return DateInterval(start: start, end: Date())
        }
    }

    // MARK: - Pickup Briefs

    func generateBrief(for session: SessionMeta) {
        guard !generatingBriefFor.contains(session.sessionId) else { return }
        generatingBriefFor.insert(session.sessionId)
        briefErrors[session.sessionId] = nil

        Task.detached(priority: .userInitiated) {
            let result = await BriefService.generate(session: session)
            await MainActor.run {
                self.generatingBriefFor.remove(session.sessionId)
                switch result {
                case .success(let parsed):
                    self.briefs[session.sessionId] = StoredBrief(
                        state: parsed.state, open: parsed.open, nextPrompt: parsed.nextPrompt,
                        generatedAt: Date(), sessionLastActivity: session.lastActivityAt, raw: parsed.raw)
                    self.saveBriefs()
                case .failure(let err):
                    self.briefErrors[session.sessionId] = err.localizedDescription
                }
            }
        }
    }

    func briefIsStale(for session: SessionMeta) -> Bool {
        guard let stored = briefs[session.sessionId] else { return false }
        guard let old = stored.sessionLastActivity, let now = session.lastActivityAt else { return false }
        return now > old.addingTimeInterval(60)
    }

    // MARK: - Handoffs

    func generateHandoff(for session: SessionMeta) {
        guard !generatingHandoffFor.contains(session.sessionId) else { return }
        generatingHandoffFor.insert(session.sessionId)
        handoffErrors[session.sessionId] = nil

        Task.detached(priority: .userInitiated) {
            let result = await HandoffService.generate(session: session)
            await MainActor.run {
                self.generatingHandoffFor.remove(session.sessionId)
                switch result {
                case .success(let parsed):
                    self.handoffs[session.sessionId] = StoredHandoff(
                        progress: parsed.progress, claude: parsed.claude, kickstart: parsed.kickstart,
                        generatedAt: Date(), sessionLastActivity: session.lastActivityAt, raw: parsed.raw)
                    self.saveHandoffs()
                case .failure(let err):
                    self.handoffErrors[session.sessionId] = err.localizedDescription
                }
            }
        }
    }

    func handoffIsStale(for session: SessionMeta) -> Bool {
        guard let stored = handoffs[session.sessionId] else { return false }
        guard let old = stored.sessionLastActivity, let now = session.lastActivityAt else { return false }
        return now > old.addingTimeInterval(60)
    }

    // MARK: - Deep search

    /// Concurrently scans every non-empty transcript for `query`; cancellable via the task.
    func runDeepSearch(_ query: String) async -> [DeepSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [] }

        // Newest sessions first (sessions is stored newest-first).
        let targets = sessions.filter { !$0.isEmpty }
        deepTotal = targets.count
        deepScanned = 0

        let metaById = Dictionary(uniqueKeysWithValues: targets.map { ($0.sessionId, $0) })
        let ordered = targets.map { $0.sessionId }

        let hits: [DeepSearchHit] = await withTaskGroup(of: (String, [RawDeepMatch]).self) { group in
            let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
            var byId: [String: [RawDeepMatch]] = [:]
            var iterator = targets.makeIterator()
            var inFlight = 0

            func addNext(_ group: inout TaskGroup<(String, [RawDeepMatch])>) -> Bool {
                guard let meta = iterator.next() else { return false }
                let url = URL(fileURLWithPath: meta.transcriptPath)
                let id = meta.sessionId
                group.addTask {
                    if Task.isCancelled { return (id, []) }
                    return (id, TranscriptScanner.deepSearch(url: url, query: q))
                }
                return true
            }

            while inFlight < maxConcurrent, addNext(&group) { inFlight += 1 }
            for await (id, matches) in group {
                byId[id] = matches
                deepScanned += 1
                if Task.isCancelled { group.cancelAll(); break }
                if addNext(&group) { inFlight += 1 }
            }

            var out: [DeepSearchHit] = []
            for id in ordered {
                guard let matches = byId[id], let meta = metaById[id] else { continue }
                for m in matches {
                    out.append(DeepSearchHit(
                        sessionId: id, sessionTitle: meta.displayTitle,
                        projectKey: meta.projectKey, projectName: meta.projectDisplayName,
                        role: m.role, snippet: m.snippet, timestamp: m.timestamp))
                    if out.count >= 200 { return out }
                }
            }
            return out
        }
        return hits
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
        case .insights: return []
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

    private func loadUsageCache() {
        guard let data = try? Data(contentsOf: usageCacheURL),
              let list = try? JSONDecoder().decode([UsageRecord].self, from: data) else { return }
        usageRecords = Dictionary(uniqueKeysWithValues: list.map { ($0.transcriptPath, $0) })
        usageLoaded = !list.isEmpty
    }

    private func saveUsageCache(_ list: [UsageRecord]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: usageCacheURL, options: .atomic)
        }
    }

    private func loadBriefs() {
        if let data = try? Data(contentsOf: briefsURL),
           let map = try? JSONDecoder().decode([String: StoredBrief].self, from: data) {
            briefs = map
        }
    }

    private func saveBriefs() {
        if let data = try? JSONEncoder().encode(briefs) {
            try? data.write(to: briefsURL, options: .atomic)
        }
    }

    private func loadHandoffs() {
        if let data = try? Data(contentsOf: handoffsURL),
           let map = try? JSONDecoder().decode([String: StoredHandoff].self, from: data) {
            handoffs = map
        }
    }

    private func saveHandoffs() {
        if let data = try? JSONEncoder().encode(handoffs) {
            try? data.write(to: handoffsURL, options: .atomic)
        }
    }
}
