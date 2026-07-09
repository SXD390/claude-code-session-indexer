import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selection: SidebarItem? = .all
    @State private var selectedSessionId: String?
    @State private var search = ""
    @AppStorage("sortOrder") private var sortRaw = SortOrder.lastActivity.rawValue
    @AppStorage("hideEmpty") private var hideEmpty = true
    @Environment(\.scenePhase) private var scenePhase

    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .lastActivity }

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
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            SessionListView(
                sessions: visibleSessions,
                selectedSessionId: $selectedSessionId,
                sortRaw: $sortRaw,
                hideEmpty: $hideEmpty
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
            .searchable(text: $search, prompt: "Search sessions")
        } detail: {
            if let session = selectedSession {
                SessionDetailView(session: session)
                    .id(session.sessionId)
            } else {
                EmptyDetailView()
            }
        }
        .navigationTitle("Claude Sessions")
        .toolbar {
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
        .task {
            store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshActive() }
        }
        .onChange(of: store.lastRefreshed) { _, _ in
            // First load: open the most recent session so the detail pane isn't empty.
            if selectedSessionId == nil {
                selectedSessionId = visibleSessions.first?.sessionId
            }
        }
    }
}

struct EmptyDetailView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            if store.isLoading && store.sessions.isEmpty {
                Text("Scanning your Claude Code sessions…")
                    .foregroundStyle(.secondary)
                ProgressView()
            } else {
                Text("Select a session")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Browse your Claude Code history, copy a resume command,\nor jump straight back into a conversation.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
