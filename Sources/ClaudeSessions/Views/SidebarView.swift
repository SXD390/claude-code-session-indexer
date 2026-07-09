import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: SessionStore
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    HStack {
                        Text("All Sessions")
                        Spacer()
                        CountBadge(count: store.sessions.count)
                    }
                } icon: {
                    Image(systemName: "tray.full")
                }
                .tag(SidebarItem.all)

                Label {
                    HStack {
                        Text("Named")
                        Spacer()
                        CountBadge(count: store.namedCount)
                    }
                } icon: {
                    Image(systemName: "tag")
                }
                .tag(SidebarItem.named)

                Label {
                    HStack {
                        Text("Running Now")
                        Spacer()
                        CountBadge(count: store.activeCount)
                    }
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(store.activeCount > 0 ? Color.green : Color.secondary)
                }
                .tag(SidebarItem.active)
            } header: {
                Text("Library")
            }

            Section {
                ForEach(store.projects) { project in
                    Label {
                        HStack {
                            Text(project.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            CountBadge(count: project.sessionCount)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .tag(SidebarItem.project(project.key))
                    .help(project.path ?? project.key)
                }
            } header: {
                Text("Projects")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                if let date = store.lastRefreshed {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("Scanning…")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
