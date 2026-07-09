import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var store: SessionStore
    let sessions: [SessionMeta]
    @Binding var selectedSessionId: String?
    @Binding var sortRaw: String
    @Binding var hideEmpty: Bool

    var body: some View {
        List(selection: $selectedSessionId) {
            ForEach(sessions) { session in
                SessionRow(
                    session: session,
                    isActive: store.activeBySessionId[session.sessionId] != nil,
                    summary: store.summaries[session.sessionId]?.text
                )
                .tag(session.sessionId)
                .contextMenu {
                    Button("Resume in Terminal") { ResumeService.resumeInTerminal(session: session) }
                    Button("Copy Resume Command") { ResumeService.copy(session.resumeCommand) }
                    Button("Copy Session ID") { ResumeService.copy(session.sessionId) }
                    Divider()
                    Button("Reveal Transcript in Finder") { ResumeService.revealTranscript(session: session) }
                    if session.cwd != nil {
                        Button("Open Project Folder") { ResumeService.openProjectInFinder(session: session) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if sessions.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "No sessions found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or filter, or start a new Claude Code session in your terminal.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Sort By", selection: $sortRaw) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Hide Empty Sessions", isOn: $hideEmpty)
                } label: {
                    Label("Sort & Filter", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort and filter options")
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionMeta
    let isActive: Bool
    let summary: String?

    private var subtitle: String? {
        if let summary, !summary.isEmpty {
            return summary.replacingOccurrences(of: "\n", with: " ")
        }
        // Avoid repeating the row title when the title is already the first prompt.
        if session.hasCustomName || session.aiTitle != nil {
            return session.firstPrompt?.replacingOccurrences(of: "\n", with: " ")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                        .help("Running now")
                }
                if session.hasCustomName {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .help("Named by you")
                }
                Text(session.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(session.projectDisplayName)
                    .lineLimit(1)
                if let date = session.lastActivityAt {
                    Text(date.formatted(.relative(presentation: .named)))
                }
                if session.userMessageCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 8))
                        Text("\(session.userMessageCount)")
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}
