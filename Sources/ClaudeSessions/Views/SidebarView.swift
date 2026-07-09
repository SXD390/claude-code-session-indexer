import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: SessionStore
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            wordmark
            list
            footer
        }
        .background(Theme.sidebarBase)
    }

    private var list: some View {
        List(selection: $selection) {
            Section {
                SidebarRow(title: "All Sessions", count: store.sessions.count,
                           isSelected: selection == .all) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.all)
                .listRowBackground(Color.clear)
                .listRowInsets(rowInsets)

                SidebarRow(title: "Named", count: store.namedCount,
                           isSelected: selection == .named) {
                    Image(systemName: "tag").foregroundStyle(Theme.coral)
                }
                .tag(SidebarItem.named)
                .listRowBackground(Color.clear)
                .listRowInsets(rowInsets)

                SidebarRow(title: "Running Now", count: store.activeCount,
                           isSelected: selection == .active) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(store.activeCount > 0 ? Theme.running : .secondary)
                }
                .tag(SidebarItem.active)
                .listRowBackground(Color.clear)
                .listRowInsets(rowInsets)
            } header: {
                sectionHeader("Library")
            }

            Section {
                ForEach(store.projects) { project in
                    SidebarRow(title: project.displayName, count: project.sessionCount,
                               isSelected: selection == .project(project.key)) {
                        ProjectDot(key: project.key, size: 9)
                    }
                    .tag(SidebarItem.project(project.key))
                    .listRowBackground(Color.clear)
                    .listRowInsets(rowInsets)
                    .help(project.path ?? project.key)
                }
            } header: {
                sectionHeader("Projects")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBase)
        .environment(\.defaultMinListRowHeight, 30)
    }

    private var rowInsets: EdgeInsets { EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8) }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
            .padding(.leading, 4)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        HStack(spacing: 10) {
            AppGlyph(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Reprise")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("for Claude Code")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.sidebarBase)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            HStack(spacing: 6) {
                if store.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Scanning sessions…")
                        .foregroundStyle(Theme.coral)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.running)
                    if let date = store.lastRefreshed {
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ready")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(store.sessions.count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Theme.sidebarBase)
    }
}

private struct SidebarRow<Icon: View>: View {
    let title: String
    let count: Int
    let isSelected: Bool
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            icon.frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            CountBadge(count: count)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Theme.coralTint.opacity(0.16)
                                 : (hovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Theme.coral.opacity(0.4) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
