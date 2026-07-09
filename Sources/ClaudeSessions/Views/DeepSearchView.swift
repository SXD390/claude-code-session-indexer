import SwiftUI

/// Results of a deep transcript search, grouped by session, shown in the content column.
struct DeepSearchResultsView: View {
    let results: [DeepSearchHit]
    let query: String
    let scanning: Bool
    let scanned: Int
    let total: Int
    @Binding var selectedSessionId: String?

    private var groups: [(id: String, hits: [DeepSearchHit])] {
        var order: [String] = []
        var byId: [String: [DeepSearchHit]] = [:]
        for hit in results {
            if byId[hit.sessionId] == nil { order.append(hit.sessionId) }
            byId[hit.sessionId, default: []].append(hit)
        }
        return order.map { ($0, byId[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            if results.isEmpty && !scanning {
                ContentUnavailableView(
                    query.count < 3 ? "Type at least 3 characters" : "No matches",
                    systemImage: "text.magnifyingglass",
                    description: Text(query.count < 3
                        ? "Deep search reads inside every transcript."
                        : "No conversation text matched “\(query)”.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            if let first = group.hits.first {
                                sessionGroup(first: first, hits: group.hits)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Theme.windowBase)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if scanning {
                ProgressView(value: total > 0 ? Double(scanned) / Double(total) : 0)
                    .frame(width: 90)
                Text("Scanning \(scanned)/\(total)…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text("\(results.count) match\(results.count == 1 ? "" : "es") in conversations")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.sidebarBase)
        .overlay(Divider().overlay(Theme.border), alignment: .bottom)
    }

    private func sessionGroup(first: DeepSearchHit, hits: [DeepSearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ProjectDot(key: first.projectKey, size: 8)
                Text(first.sessionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(first.projectName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)

            ForEach(hits) { hit in
                Button {
                    selectedSessionId = hit.sessionId
                } label: {
                    HitRow(hit: hit, query: query)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct HitRow: View {
    let hit: DeepSearchHit
    let query: String
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: hit.role == "user" ? "person.fill" : "sparkle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hit.role == "user" ? Theme.coral : .secondary)
                .padding(.top, 3)
            Text(highlighted)
                .font(.system(size: 12))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Theme.coralTint.opacity(0.10) : Theme.field,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// Snippet with each case-insensitive match of the query emphasized in coral.
    private var highlighted: AttributedString {
        var attr = AttributedString(hit.snippet)
        attr.foregroundColor = .secondary
        guard !query.isEmpty else { return attr }

        var searchStart = attr.startIndex
        while searchStart < attr.endIndex,
              let r = attr[searchStart...].range(of: query, options: .caseInsensitive) {
            attr[r].foregroundColor = Theme.coral
            attr[r].font = .system(size: 12, weight: .bold)
            searchStart = r.upperBound
        }
        return attr
    }
}
