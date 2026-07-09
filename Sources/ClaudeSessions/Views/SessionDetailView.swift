import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    let session: SessionMeta

    @State private var preview: [PreviewMessage] = []
    @State private var previewLoaded = false
    @State private var copiedCommand = false
    @State private var copiedId = false
    @Environment(\.colorScheme) private var scheme

    private var isActive: Bool { store.activeBySessionId[session.sessionId] != nil }
    private var accent: Color { Theme.projectColor(for: session.projectKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                resumeCard
                summaryCard
                metadataCard
                conversationCard
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.windowBase)
        .task(id: session.sessionId) {
            previewLoaded = false
            let url = URL(fileURLWithPath: session.transcriptPath)
            let messages = await Task.detached(priority: .userInitiated) {
                TranscriptScanner.extractPreview(url: url)
            }.value
            preview = messages
            previewLoaded = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(session.displayTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }

            if session.hasCustomName, let ai = session.aiTitle {
                Text(ai)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Project path chip + badges
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ProjectDot(key: session.projectKey, size: 8)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                    Text(session.cwd ?? session.projectKey)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.field, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))

                if isActive { RunningPill() }
                if session.hasCustomName { NamedPill() }
            }

            // Quick stats
            HStack(spacing: 10) {
                StatChip(systemImage: "arrow.up.message.fill",
                         value: "\(session.userMessageCount)", label: "Prompts", tint: Theme.coral)
                StatChip(systemImage: "sparkles",
                         value: "\(session.assistantMessageCount)", label: "Replies", tint: accent)
                StatChip(systemImage: "clock.fill",
                         value: durationString(), label: "Duration", tint: .secondary)
            }
        }
    }

    private func durationString() -> String {
        guard let a = session.createdAt, let b = session.lastActivityAt, b > a else { return "—" }
        let secs = b.timeIntervalSince(a)
        if secs < 60 { return "<1m" }
        let fmt = DateComponentsFormatter()
        fmt.allowedUnits = [.day, .hour, .minute]
        fmt.maximumUnitCount = 2
        fmt.unitsStyle = .abbreviated
        return fmt.string(from: secs) ?? "—"
    }

    // MARK: - Resume

    private var resumeCard: some View {
        Card(title: "Resume", systemImage: "arrow.uturn.forward", accent: Theme.coral) {
            VStack(alignment: .leading, spacing: 12) {
                // Terminal-style command block
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.coralHi)
                        .padding(.top, 2)
                    Text(session.resumeCommand)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xEDE6DF))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        ResumeService.copy(session.resumeCommand)
                        flash($copiedCommand)
                    } label: {
                        Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(copiedCommand ? Theme.running : Color(hex: 0xBFB6AD))
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Copy the resume command")
                }
                .padding(14)
                .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))

                HStack(spacing: 10) {
                    Button {
                        ResumeService.resumeInTerminal(session: session)
                    } label: {
                        Label("Resume in Terminal", systemImage: "terminal.fill")
                    }
                    .buttonStyle(GradientButtonStyle())
                    .help("Opens your default terminal and resumes this session")

                    Button {
                        ResumeService.copy(session.sessionId)
                        flash($copiedId)
                    } label: {
                        Label(copiedId ? "Copied" : "Session ID", systemImage: copiedId ? "checkmark" : "number")
                    }
                    .buttonStyle(SoftButtonStyle())

                    Button {
                        ResumeService.revealTranscript(session: session)
                    } label: {
                        Label("Transcript", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .help("Reveal the .jsonl transcript in Finder")

                    Spacer()
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        Card(title: "Summary", systemImage: "sparkles", accent: Theme.coral, gradientIcon: true) {
            VStack(alignment: .leading, spacing: 12) {
                if let stored = store.summaries[session.sessionId] {
                    Text(stored.text)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text("Generated \(stored.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if store.summaryIsStale(for: session) {
                            Label("New activity since", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        summaryActionButton(label: "Regenerate")
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No summary yet")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Generate a concise AI recap with `claude -p` (Haiku).")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        summaryActionButton(label: "Generate")
                    }
                }

                if let error = store.summaryErrors[session.sessionId] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryActionButton(label: String) -> some View {
        if store.generatingSummaryFor.contains(session.sessionId) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Summarizing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                store.generateSummary(for: session)
            } label: {
                Label(label, systemImage: "sparkles")
            }
            .buttonStyle(GradientButtonStyle())
        }
    }

    // MARK: - Metadata

    private var metadataCard: some View {
        Card(title: "Details", systemImage: "info.circle", accent: accent) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    metaCell("Created", session.createdAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    metaCell("Last activity", session.lastActivityAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                }
                GridRow {
                    metaCell("Your prompts", "\(session.userMessageCount)")
                    metaCell("Assistant replies", "\(session.assistantMessageCount)")
                }
                GridRow {
                    metaCell("Git branch", session.gitBranch ?? "—")
                    metaCell("Model", session.model.map(shortModelName) ?? "—")
                }
                GridRow {
                    metaCell("Transcript size", ByteCountFormatter.string(fromByteCount: session.fileSize, countStyle: .file))
                    metaCell("CLI version", session.cliVersion ?? "—")
                }
                Divider().gridCellColumns(2).overlay(Theme.border)
                GridRow {
                    metaCell("Session ID", session.sessionId)
                        .gridCellColumns(2)
                }
            }
        }
    }

    private func metaCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func shortModelName(_ id: String) -> String {
        id.replacingOccurrences(of: "-[0-9]{8}$", with: "", options: .regularExpression)
    }

    // MARK: - Conversation preview

    private var conversationCard: some View {
        Card(title: "Conversation", systemImage: "bubble.left.and.bubble.right.fill", accent: accent) {
            if !previewLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                    Text("Loading transcript…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if preview.isEmpty {
                Text("No readable messages in this transcript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(preview) { message in
                        MessageBubble(message: message)
                    }
                    if preview.count >= 400 {
                        Text("Preview truncated — open the transcript for the full conversation.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func flash(_ binding: Binding<Bool>) {
        binding.wrappedValue = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            binding.wrappedValue = false
        }
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    var accent: Color = Theme.coral
    var gradientIcon: Bool = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                iconBadge
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .cardShadow(scheme)
    }

    @ViewBuilder
    private var iconBadge: some View {
        if gradientIcon {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.coralGradient)
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent.opacity(0.14))
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent))
        }
    }
}

struct MessageBubble: View {
    let message: PreviewMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !isUser {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                    Text(isUser ? "You" : "Claude")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let ts = message.timestamp {
                        Text(ts.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    if isUser {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                    }
                }
                Text(message.text)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(bubbleBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isUser ? Theme.coral.opacity(0.22) : Theme.border, lineWidth: 1)
                    )
            }
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isUser ? Theme.coralTint.opacity(0.12) : Theme.cardRaised)
    }
}
