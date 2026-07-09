import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selection: SidebarItem? = .all
    @State private var selectedSessionId: String?
    @State private var search = ""
    @AppStorage("sortOrder") private var sortRaw = SortOrder.lastActivity.rawValue
    @AppStorage("hideEmpty") private var hideEmpty = true
    @Environment(\.scenePhase) private var scenePhase

    // Insights range
    @State private var rangePreset: RangePreset = .d30
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd = Date()

    // Deep search
    @State private var deepSearch = false
    @State private var deepResults: [DeepSearchHit] = []
    @State private var deepSearching = false
    @State private var deepTask: Task<Void, Never>?

    // Project journal
    @State private var showJournal = false

    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .lastActivity }

    private var isInsights: Bool { selection == .insights }

    private var selectedProjectKey: String? {
        if case .project(let key) = selection { return key }
        return nil
    }

    private var deepActive: Bool {
        deepSearch && search.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private var range: DateInterval? {
        store.dateInterval(preset: rangePreset, customStart: customStart, customEnd: customEnd)
    }

    private var visibleSessions: [SessionMeta] {
        store.filteredSessions(for: selection ?? .all, search: search, sort: sort, hideEmpty: hideEmpty)
    }

    private var selectedSession: SessionMeta? {
        visibleSessions.first { $0.sessionId == selectedSessionId }
            ?? store.sessions.first { $0.sessionId == selectedSessionId }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 244, max: 300)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 460, ideal: 620)
        }
        .navigationTitle("Reprise")
        .tint(Theme.coral)
        .frame(minWidth: 960, minHeight: 640)
        .toolbar { toolbarContent }
        .task { store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshActive() }
        }
        .onChange(of: store.lastRefreshed) { _, _ in
            if selectedSessionId == nil {
                selectedSessionId = store.recentSessions(1).first?.sessionId
            }
        }
        .onChange(of: selection) { _, _ in showJournal = false }
        .onChange(of: search) { _, _ in scheduleDeepSearch() }
        .onChange(of: deepSearch) { _, on in
            if on { scheduleDeepSearch() } else { deepTask?.cancel(); deepResults = []; deepSearching = false }
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private var contentColumn: some View {
        if isInsights {
            InsightsSidePanel(preset: $rangePreset, customStart: $customStart, customEnd: $customEnd)
        } else if deepActive {
            DeepSearchResultsView(
                results: deepResults, query: search.trimmingCharacters(in: .whitespacesAndNewlines),
                scanning: deepSearching, scanned: store.deepScanned, total: store.deepTotal,
                selectedSessionId: $selectedSessionId)
            .searchable(text: $search, prompt: "Search inside conversations")
        } else {
            SessionListView(
                sessions: visibleSessions,
                selectedSessionId: $selectedSessionId,
                sortRaw: $sortRaw,
                hideEmpty: $hideEmpty
            )
            .searchable(text: $search, prompt: "Search sessions")
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if isInsights {
            InsightsView(range: range, rangeLabel: rangePreset.label, onSelect: openSession)
        } else if let key = selectedProjectKey, showJournal {
            JournalView(projectKey: key, onSelect: openSession)
        } else if let session = selectedSession {
            SessionDetailView(session: session).id(session.sessionId)
        } else {
            OverviewDashboard(onSelect: { selectedSessionId = $0 })
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectedProjectKey != nil {
            ToolbarItem(placement: .automatic) {
                Button {
                    showJournal.toggle()
                } label: {
                    Label(showJournal ? "Sessions" : "Journal",
                          systemImage: showJournal ? "list.bullet" : "book")
                }
                .help(showJournal ? "Back to session detail" : "Open this project's journal")
            }
        }
        if !isInsights {
            ToolbarItem(placement: .automatic) {
                Button {
                    deepSearch.toggle()
                } label: {
                    Label("Search in conversations", systemImage: "text.magnifyingglass")
                        .foregroundStyle(deepSearch ? Theme.coral : .primary)
                }
                .help(deepSearch ? "Deep search on — searching inside transcripts" : "Search inside conversations")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.refresh()
            } label: {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .help("Rescan sessions (⌘R)")
            .disabled(store.isLoading)
        }
    }

    // MARK: - Actions

    private func openSession(_ id: String) {
        selectedSessionId = id
        showJournal = false
        if isInsights { selection = .all }
    }

    private func scheduleDeepSearch() {
        deepTask?.cancel()
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard deepSearch, q.count >= 3 else {
            deepResults = []; deepSearching = false
            return
        }
        deepTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)   // debounce keystrokes
            if Task.isCancelled { return }
            deepSearching = true
            let results = await store.runDeepSearch(q)
            if Task.isCancelled { return }
            deepResults = results
            deepSearching = false
        }
    }
}

// MARK: - Overview dashboard (no-selection state)

struct OverviewDashboard: View {
    @EnvironmentObject var store: SessionStore
    let onSelect: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            if store.isLoading && store.sessions.isEmpty {
                scanning
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    greeting
                    statGrid
                    boards
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(Theme.windowBase)
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            AppGlyph(size: 46)
            Text("Scanning your Claude Code sessions…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 460)
    }

    private var greeting: some View {
        HStack(spacing: 14) {
            AppGlyph(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome back")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Pick up where you left off, or browse your history.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 14)], spacing: 14) {
            BigStat(value: store.sessions.count, label: "Total sessions",
                    systemImage: "square.stack.3d.up.fill", tint: Theme.coral, scheme: scheme)
            BigStat(value: store.namedCount, label: "Named",
                    systemImage: "tag.fill", tint: Color(hex: 0x9B7ED1), scheme: scheme)
            BigStat(value: store.activeCount, label: "Running now",
                    systemImage: "dot.radiowaves.left.and.right", tint: Theme.running,
                    scheme: scheme, live: store.activeCount > 0)
            BigStat(value: store.totalPromptCount, label: "Prompts",
                    systemImage: "arrow.up.message.fill", tint: Color(hex: 0x57A6C9), scheme: scheme)
        }
    }

    /// Two dashboard cards side-by-side when the pane is wide, stacked when narrow.
    private var boards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                topProjects.frame(minWidth: 288, maxWidth: .infinity)
                recent.frame(minWidth: 288, maxWidth: .infinity)
            }
            VStack(spacing: 16) {
                topProjects
                recent
            }
        }
    }

    // MARK: Top projects with bars

    private var topProjects: some View {
        let projects = store.topProjects(5)
        let maxCount = max(projects.first?.sessionCount ?? 1, 1)
        return DashCard(title: "Top projects", systemImage: "chart.bar.fill", scheme: scheme) {
            if projects.isEmpty {
                emptyLine("No projects yet")
            } else {
                VStack(spacing: 12) {
                    ForEach(projects) { p in
                        HStack(spacing: 10) {
                            ProjectDot(key: p.key, size: 9)
                            Text(p.displayName)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                                .frame(width: 116, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.field)
                                    Capsule()
                                        .fill(Theme.projectColor(for: p.key))
                                        .frame(width: max(6, geo.size.width * CGFloat(p.sessionCount) / CGFloat(maxCount)))
                                }
                            }
                            .frame(height: 8)
                            Text("\(p.sessionCount)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Recent quick-resume

    private var recent: some View {
        let sessions = store.recentSessions(5)
        return DashCard(title: "Jump back in", systemImage: "clock.arrow.circlepath", scheme: scheme) {
            if sessions.isEmpty {
                emptyLine("No recent sessions")
            } else {
                VStack(spacing: 4) {
                    ForEach(sessions) { s in
                        RecentRow(
                            session: s,
                            isActive: store.activeBySessionId[s.sessionId] != nil,
                            onSelect: { onSelect(s.sessionId) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

// MARK: - Dashboard components

private struct BigStat: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color
    let scheme: ColorScheme
    var live: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                if live { RunningDot(size: 7) }
            }
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .cardShadow(scheme)
    }
}

private struct DashCard<Content: View>: View {
    let title: String
    let systemImage: String
    let scheme: ColorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .cardShadow(scheme)
    }
}

private struct RecentRow: View {
    let session: SessionMeta
    let isActive: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ProjectDot(key: session.projectKey, size: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if isActive { RunningDot(size: 6) }
                        Text(session.displayTitle)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text(session.projectDisplayName).lineLimit(1)
                        if let d = session.lastActivityAt {
                            Text("·").foregroundStyle(.quaternary)
                            Text(d.formatted(.relative(presentation: .named)))
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 6)
                Image(systemName: "arrow.uturn.forward.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(hovering ? Theme.coral : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hovering ? Theme.coralTint.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
