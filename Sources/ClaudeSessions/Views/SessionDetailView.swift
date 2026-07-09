import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    let session: SessionMeta

    @State private var preview: [PreviewMessage] = []
    @State private var previewLoaded = false
    @State private var copiedCommand = false
    @State private var copiedId = false

    private var isActive: Bool { store.activeBySessionId[session.sessionId] != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                resumeCard
                summaryCard
                metadataCard
                conversationCard
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if session.hasCustomName {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(Color.accentColor)
                }
                Text(session.displayTitle)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                if isActive {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("Running")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
                }
            }
            if session.hasCustomName, let ai = session.aiTitle {
                Text(ai)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption)
                Text(session.cwd ?? session.projectKey)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Resume

    private var resumeCard: some View {
        Card(title: "Resume", systemImage: "arrow.uturn.forward.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(session.resumeCommand)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 6))

                    Button {
                        ResumeService.copy(session.resumeCommand)
                        flash($copiedCommand)
                    } label: {
                        Label(copiedCommand ? "Copied" : "Copy", systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
                            .frame(minWidth: 64)
                    }
                    .help("Copy the resume command")
                }

                HStack(spacing: 10) {
                    Button {
                        ResumeService.resumeInTerminal(session: session)
                    } label: {
                        Label("Resume in Terminal", systemImage: "terminal")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Opens your default terminal and resumes this session")

                    Button {
                        ResumeService.copy(session.sessionId)
                        flash($copiedId)
                    } label: {
                        Label(copiedId ? "Copied" : "Copy Session ID", systemImage: copiedId ? "checkmark" : "number")
                    }

                    Button {
                        ResumeService.revealTranscript(session: session)
                    } label: {
                        Label("Transcript", systemImage: "doc.text.magnifyingglass")
                    }
                    .help("Reveal the .jsonl transcript in Finder")
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        Card(title: "Summary", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 10) {
                if let stored = store.summaries[session.sessionId] {
                    Text(stored.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Text("Generated \(stored.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if store.summaryIsStale(for: session) {
                            Label("Session has new activity since", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        regenerateButton(label: "Regenerate")
                    }
                } else {
                    HStack(spacing: 10) {
                        Text("Generate a 2–3 sentence AI summary of this session using `claude -p` (Haiku).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        regenerateButton(label: "Generate Summary")
                    }
                }

                if let error = store.summaryErrors[session.sessionId] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func regenerateButton(label: String) -> some View {
        if store.generatingSummaryFor.contains(session.sessionId) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
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
        }
    }

    // MARK: - Metadata

    private var metadataCard: some View {
        Card(title: "Details", systemImage: "info.circle") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
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
                GridRow {
                    metaCell("Session ID", session.sessionId)
                        .gridCellColumns(2)
                }
            }
        }
    }

    private func metaCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    private func shortModelName(_ id: String) -> String {
        id.replacingOccurrences(of: "-[0-9]{8}$", with: "", options: .regularExpression)
    }

    // MARK: - Conversation preview

    private var conversationCard: some View {
        Card(title: "Conversation", systemImage: "bubble.left.and.bubble.right") {
            if !previewLoaded {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading transcript…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if preview.isEmpty {
                Text("No readable messages in this transcript.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(preview) { message in
                        MessageBubble(message: message)
                    }
                    if preview.count >= 400 {
                        Text("Preview truncated — open the transcript for the full conversation.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

struct MessageBubble: View {
    let message: PreviewMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isUser ? "person.circle.fill" : "sparkle")
                    .font(.caption)
                    .foregroundStyle(isUser ? Color.accentColor : Color.purple)
                Text(isUser ? "You" : "Claude")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let ts = message.timestamp {
                    Text(ts.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    isUser ? Color.accentColor.opacity(0.08) : Color(nsColor: .quaternarySystemFill),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
    }
}
