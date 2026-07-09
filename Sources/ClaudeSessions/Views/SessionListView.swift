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
                    summary: store.summaries[session.sessionId]?.text,
                    isSelected: session.sessionId == selectedSessionId
                )
                .tag(session.sessionId)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button("Resume in Terminal") { ResumeService.resumeInTerminal(session: session) }
                    Button("Copy Resume Command") { ResumeService.copy(session.resumeCommand) }
                    Button("Copy Session ID") { ResumeService.copy(session.sessionId) }
                    Divider()
                    Button("Prepare Handoff") {
                        selectedSessionId = session.sessionId
                        store.generateHandoff(for: session)
                    }
                    Divider()
                    Button("Reveal Transcript in Finder") { ResumeService.revealTranscript(session: session) }
                    if session.cwd != nil {
                        Button("Open Project Folder") { ResumeService.openProjectInFinder(session: session) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.windowBase)
        .tint(Theme.coral)
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
    var isSelected: Bool = false
    @State private var hovering = false

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
        VStack(alignment: .leading, spacing: 4) {
            // Level 1 — title + status
            HStack(spacing: 6) {
                if isActive { RunningDot(size: 7) }
                Text(session.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if session.hasCustomName { NamedPill(compact: true) }
            }

            // Level 2 — summary / first prompt
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Level 3 — project · time · prompts
            HStack(spacing: 6) {
                ProjectDot(key: session.projectKey, size: 7)
                Text(session.projectDisplayName)
                    .lineLimit(1)
                if let date = session.lastActivityAt {
                    Text("·").foregroundStyle(.quaternary)
                    Text(date.formatted(.relative(presentation: .named)))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if session.userMessageCount > 0 {
                    MetaChip(systemImage: "bubble.left.fill", text: "\(session.userMessageCount)", tint: .secondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Theme.coral.opacity(0.45) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? Theme.coralTint.opacity(0.16)
                             : (hovering ? Color.primary.opacity(0.05) : Color.clear))
    }
}
