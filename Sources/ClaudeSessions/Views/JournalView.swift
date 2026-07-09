import SwiftUI
import AppKit

/// A chronological, story-order timeline of one project's sessions, with a
/// changelog-style Markdown export.
struct JournalView: View {
    @EnvironmentObject var store: SessionStore
    let projectKey: String
    let onSelect: (String) -> Void

    @State private var copied = false
    @Environment(\.colorScheme) private var scheme

    struct Entry: Identifiable {
        let session: SessionMeta
        let date: Date
        let cost: Double
        let activeSeconds: Double
        var id: String { session.sessionId }
    }

    private var projectName: String {
        store.projects.first { $0.key == projectKey }?.displayName ?? projectKey
    }

    private var entries: [Entry] {
        store.sessions
            .filter { $0.projectKey == projectKey && !$0.isEmpty }
            .map { s in
                let rec = store.usageRecords[s.transcriptPath]
                return Entry(
                    session: s,
                    date: s.createdAt ?? s.lastActivityAt ?? .distantPast,
                    cost: rec?.totalCost ?? 0,
                    activeSeconds: rec?.totalActiveSeconds ?? 0)
            }
            .sorted { $0.date < $1.date }   // oldest first — reads like a story
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if entries.isEmpty {
                    Text("No sessions in this project yet.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    timeline
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.windowBase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.projectColor(for: projectKey))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(projectName) Journal")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("\(entries.count) sessions · \(Fmt.duration(entries.reduce(0) { $0 + $1.activeSeconds })) · \(Fmt.cost(entries.reduce(0) { $0 + $1.cost })) est.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    exportMarkdown()
                } label: {
                    Label("Export Markdown", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GradientButtonStyle())

                Button {
                    ResumeService.copy(buildMarkdown())
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy Markdown", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SoftButtonStyle())
                Spacer()
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(monthGroups.enumerated()), id: \.offset) { _, group in
                Text(group.month)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                ForEach(group.entries) { entry in
                    JournalRow(entry: entry, projectKey: projectKey,
                               summary: store.summaries[entry.session.sessionId]?.text,
                               onSelect: { onSelect(entry.session.sessionId) })
                }
            }
        }
    }

    private var monthGroups: [(month: String, entries: [Entry])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var result: [(String, [Entry])] = []
        for entry in entries {
            let key = fmt.string(from: entry.date)
            if result.last?.0 == key {
                result[result.count - 1].1.append(entry)
            } else {
                result.append((key, [entry]))
            }
        }
        return result.map { ($0.0, $0.1) }
    }

    // MARK: - Markdown

    private func buildMarkdown() -> String {
        var lines: [String] = ["# \(projectName) — Claude Code Journal", ""]
        let dfmt = DateFormatter()
        dfmt.dateFormat = "yyyy-MM-dd"
        for entry in entries {
            let s = entry.session
            let dur = entry.activeSeconds > 0 ? Fmt.duration(entry.activeSeconds) : wallDuration(s)
            let cost = entry.cost > 0 ? ", ~\(Fmt.cost(entry.cost))" : ""
            lines.append("## \(dfmt.string(from: entry.date)) — \(s.displayTitle) (\(dur), \(s.userMessageCount) prompts\(cost))")
            let body = store.summaries[s.sessionId]?.text
                ?? s.firstPrompt
                ?? "No summary available."
            lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func wallDuration(_ s: SessionMeta) -> String {
        guard let a = s.createdAt, let b = s.lastActivityAt, b > a else { return "—" }
        return Fmt.duration(b.timeIntervalSince(a))
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        let safe = projectName.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = "\(safe.isEmpty ? "project" : safe)-journal.md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? buildMarkdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct JournalRow: View {
    let entry: JournalView.Entry
    let projectKey: String
    let summary: String?
    let onSelect: () -> Void
    @State private var hovering = false

    private var s: SessionMeta { entry.session }

    private var durationString: String {
        if entry.activeSeconds > 0 { return Fmt.duration(entry.activeSeconds) }
        guard let a = s.createdAt, let b = s.lastActivityAt, b > a else { return "—" }
        return Fmt.duration(b.timeIntervalSince(a))
    }

    private var body_: String {
        if let summary, !summary.isEmpty { return summary.replacingOccurrences(of: "\n", with: " ") }
        if let p = s.firstPrompt, !p.isEmpty { return p.replacingOccurrences(of: "\n", with: " ") }
        return "No summary yet."
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Timeline rail
                VStack(spacing: 0) {
                    Circle().fill(Theme.projectColor(for: projectKey)).frame(width: 9, height: 9)
                    Rectangle().fill(Theme.border).frame(width: 1.5).frame(maxHeight: .infinity)
                }
                .padding(.top, 5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        if s.hasCustomName { NamedPill(compact: true) }
                        Spacer()
                    }
                    Text(s.displayTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 12) {
                        MetaChip(systemImage: "clock", text: durationString)
                        MetaChip(systemImage: "arrow.up.message", text: "\(s.userMessageCount)")
                        if entry.cost > 0 {
                            MetaChip(systemImage: "dollarsign.circle", text: Fmt.cost(entry.cost))
                        }
                    }

                    Text(body_)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? Theme.cardRaised : Theme.card,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(hovering ? Theme.borderStrong : Theme.border, lineWidth: 1))
                .padding(.bottom, 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
