import SwiftUI
import AppKit

struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    let session: SessionMeta

    @State private var preview: [PreviewMessage] = []
    @State private var previewLoaded = false
    @State private var copiedCommand = false
    @State private var copiedId = false
    @State private var copiedBrief = false
    @Environment(\.colorScheme) private var scheme

    private var isActive: Bool { store.activeBySessionId[session.sessionId] != nil }
    private var accent: Color { Theme.projectColor(for: session.projectKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                resumeCard
                briefCard
                HandoffCard(session: session)
                summaryCard
                usageCard
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

    // MARK: - Pickup Brief

    private var briefCard: some View {
        Card(title: "Pickup Brief", systemImage: "flag.checkered", accent: Theme.coral, gradientIcon: true) {
            VStack(alignment: .leading, spacing: 14) {
                if let brief = store.briefs[session.sessionId] {
                    briefContent(brief)
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get back into flow")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Generate a resume brief: where things stand, what's open, and a ready-to-paste next prompt.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        briefActionButton(label: "Generate")
                    }
                }
                if let error = store.briefErrors[session.sessionId] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func briefContent(_ brief: StoredBrief) -> some View {
        // STATE
        if !brief.state.isEmpty {
            Text(brief.state)
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // OPEN threads
        if !brief.open.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("OPEN THREADS")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                ForEach(Array(brief.open.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Theme.coral)
                            .padding(.top, 6)
                        Text(item)
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        // NEXT PROMPT — terminal-style copyable block
        if !brief.nextPrompt.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("NEXT PROMPT")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.coralHi)
                        .padding(.top, 2)
                    Text(brief.nextPrompt)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xEDE6DF))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))

                Button {
                    ResumeService.copy(brief.nextPrompt)
                    flash($copiedBrief)
                } label: {
                    Label(copiedBrief ? "Copied to clipboard" : "Copy next prompt",
                          systemImage: copiedBrief ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GradientButtonStyle())
            }
        }

        // Footer: staleness + regenerate
        HStack(spacing: 8) {
            Text("Generated \(brief.generatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.tertiary)
            if store.briefIsStale(for: session) {
                Label("New activity since", systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            briefActionButton(label: "Regenerate")
        }
    }

    @ViewBuilder
    private func briefActionButton(label: String) -> some View {
        if store.generatingBriefFor.contains(session.sessionId) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Briefing…").font(.callout).foregroundStyle(.secondary)
            }
        } else if label == "Regenerate" {
            Button { store.generateBrief(for: session) } label: {
                Label(label, systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SoftButtonStyle())
        } else {
            Button { store.generateBrief(for: session) } label: {
                Label(label, systemImage: "flag.checkered")
            }
            .buttonStyle(GradientButtonStyle())
        }
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageCard: some View {
        if let rec = store.usageRecord(for: session), rec.totalTokens > 0 {
            Card(title: "Usage", systemImage: "gauge.with.dots.needle.33percent", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        tokenCell("Input", rec.totalInput, "arrow.down.circle")
                        tokenCell("Output", rec.totalOutput, "arrow.up.circle")
                        tokenCell("Cache read", rec.totalCacheRead, "arrow.clockwise.circle")
                        tokenCell("Cache write", rec.totalCacheWrite, "square.and.arrow.down")
                    }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.cost(rec.totalCost))
                                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text("Est. cost (API-equivalent)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        FlowChips(models: rec.perModel)
                    }
                }
            }
        }
    }

    private func tokenCell(_ label: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            Text(Fmt.tokens(value))
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
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

// MARK: - Handoff

/// Packages a finished session into PROGRESS.md / CLAUDE.md files written into the
/// project directory so a fresh Claude Code session can pick the work back up.
/// Nothing is written until the user explicitly clicks "Write to Project".
struct HandoffCard: View {
    @EnvironmentObject var store: SessionStore
    let session: SessionMeta

    @State private var alsoUpdateClaude = false
    @State private var initedFor: Date?
    @State private var writtenPaths: [URL] = []
    @State private var writeError: String?
    @State private var copiedKickstart = false
    @State private var copiedProgress = false
    @State private var copiedClaude = false
    @Environment(\.colorScheme) private var scheme

    private var handoff: StoredHandoff? { store.handoffs[session.sessionId] }
    private var isGenerating: Bool { store.generatingHandoffFor.contains(session.sessionId) }

    private var cwdURL: URL? {
        guard let cwd = session.cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd)
    }
    private var cwdValid: Bool {
        guard let url = cwdURL else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
    private var progressExists: Bool {
        guard let url = cwdURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("PROGRESS.md").path)
    }
    private var claudeExists: Bool {
        guard let url = cwdURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("CLAUDE.md").path)
    }

    /// Current on-disk contents of a file inside the project dir, or nil if unreadable / absent.
    private func onDisk(_ name: String) -> String? {
        guard let url = cwdURL else { return nil }
        return try? String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
    }

    /// The EXACT bytes `writeToProject` would produce for PROGRESS.md — used for both the diff
    /// preview and the "Copy PROGRESS.md" action, so preview, copy, and write can never diverge.
    private func mergedProgressContent(_ h: StoredHandoff) -> String {
        HandoffService.mergedProgress(
            existing: onDisk("PROGRESS.md"),
            projectName: session.projectDisplayName,
            section: h.progress)
    }

    /// The EXACT bytes `writeToProject` would produce for CLAUDE.md (merged marker block).
    private func mergedClaudeContent(_ claude: String) -> String {
        HandoffService.mergedClaude(
            existing: onDisk("CLAUDE.md"),
            block: HandoffService.markerBlock(content: claude))
    }

    var body: some View {
        Card(title: "Handoff", systemImage: "shippingbox.fill", accent: Theme.coral, gradientIcon: true) {
            VStack(alignment: .leading, spacing: 14) {
                if let h = handoff {
                    generated(h)
                } else {
                    empty
                }
                if let error = store.handoffErrors[session.sessionId] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .onAppear { syncToggle() }
        .onChange(of: handoff?.generatedAt) { _, _ in syncToggle() }
    }

    /// On first display of a (new) handoff: default the CLAUDE.md toggle ON when the file
    /// doesn't exist yet, OFF when it does (respect the user's own file); clear write state.
    private func syncToggle() {
        guard let gen = handoff?.generatedAt, gen != initedFor else { return }
        initedFor = gen
        alsoUpdateClaude = !claudeExists
        writtenPaths = []
        writeError = nil
    }

    // MARK: Empty state

    private var empty: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Package this session's work")
                    .font(.system(size: 13, weight: .semibold))
                Text("Prepare a handoff so a fresh Claude Code session can pick it up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            actionButton(label: "Prepare Handoff")
        }
    }

    // MARK: Generated state

    @ViewBuilder
    private func generated(_ h: StoredHandoff) -> some View {
        if !cwdValid {
            Label("Project directory not found — files can't be written for this session.",
                  systemImage: "folder.badge.questionmark")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        // PROGRESS.md — diff preview of exactly what "Write to Project" would produce.
        section(label: "PROGRESS.md",
                note: progressExists ? "prepends a new dated section — existing content is preserved"
                                     : "will create PROGRESS.md") {
            if cwdValid {
                diffBox(old: onDisk("PROGRESS.md") ?? "",
                        new: mergedProgressContent(h),
                        isNewFile: !progressExists,
                        maxHeight: 240)
            } else {
                // No valid project dir → no diff; still show the generated section so it can be copied.
                fileBox(h.progress, maxHeight: 210)
            }
        }

        // CLAUDE.md — diff preview (hidden entirely when the model returned NONE)
        if let claude = h.claude, !claude.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    sectionLabel("CLAUDE.md")
                    Spacer()
                    Toggle("Also update CLAUDE.md", isOn: $alsoUpdateClaude)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .tint(Theme.coral)
                        .disabled(!writtenPaths.isEmpty)
                }
                Text(claudeExists ? "appends a marked section — your existing CLAUDE.md is never overwritten"
                                  : "will create CLAUDE.md")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                if alsoUpdateClaude {
                    if cwdValid {
                        diffBox(old: onDisk("CLAUDE.md") ?? "",
                                new: mergedClaudeContent(claude),
                                isNewFile: !claudeExists,
                                maxHeight: 190)
                    } else {
                        fileBox(HandoffService.markerBlock(content: claude), maxHeight: 170)
                    }
                }
            }
        }

        // KICKSTART — copyable terminal block (never written to disk)
        if !h.kickstart.isEmpty {
            kickstartBlock(h.kickstart)
        }

        // Write state / actions
        if writtenPaths.isEmpty {
            actionsRow(h)
        } else {
            writtenState
        }

        if let err = writeError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionsRow(_ h: StoredHandoff) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    performWrite(h)
                } label: {
                    Label("Write to Project", systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(!cwdValid)
                .help(cwdValid ? "Writes PROGRESS.md" + (writesClaude(h) ? " and CLAUDE.md" : "") + " into \(session.cwd ?? "")"
                               : "No valid project directory for this session")

                actionButton(label: "Regenerate")

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Generated \(h.generatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.tertiary)
                    if store.handoffIsStale(for: session) {
                        Label("New activity since", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            // Copy-only: put the resulting merged file(s) on the clipboard without writing to disk.
            HStack(spacing: 10) {
                Button {
                    ResumeService.copy(mergedProgressContent(h))
                    flashCopy($copiedProgress)
                } label: {
                    Label(copiedProgress ? "Copied PROGRESS.md" : "Copy PROGRESS.md",
                          systemImage: copiedProgress ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SoftButtonStyle())
                .help("Copy the resulting PROGRESS.md to the clipboard — nothing is written to disk")

                if let claude = h.claude, !claude.isEmpty {
                    Button {
                        ResumeService.copy(mergedClaudeContent(claude))
                        flashCopy($copiedClaude)
                    } label: {
                        Label(copiedClaude ? "Copied CLAUDE.md" : "Copy CLAUDE.md",
                              systemImage: copiedClaude ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .help("Copy the resulting CLAUDE.md to the clipboard — nothing is written to disk")
                }

                Spacer()
            }
        }
    }

    /// Flip a copied-flag on for 1.5s (flash-to-checkmark), matching the app's other copy buttons.
    private func flashCopy(_ binding: Binding<Bool>) {
        binding.wrappedValue = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            binding.wrappedValue = false
        }
    }

    private var writtenState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.running)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wrote \(writtenPaths.count) file\(writtenPaths.count == 1 ? "" : "s") to the project")
                        .font(.system(size: 12.5, weight: .semibold))
                    ForEach(writtenPaths, id: \.self) { url in
                        Text(url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(writtenPaths)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(GradientButtonStyle())

                actionButton(label: "Regenerate")
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.running.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.running.opacity(0.25), lineWidth: 1))
    }

    private func writesClaude(_ h: StoredHandoff) -> Bool {
        alsoUpdateClaude && (h.claude?.isEmpty == false)
    }

    private func performWrite(_ h: StoredHandoff) {
        writeError = nil
        let req = HandoffService.WriteRequest(
            session: session,
            progressSection: h.progress,
            claudeContent: h.claude,
            includeClaudeMd: alsoUpdateClaude)
        do {
            writtenPaths = try HandoffService.writeToProject(req)
        } catch {
            writtenPaths = []
            writeError = error.localizedDescription
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func actionButton(label: String) -> some View {
        if isGenerating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Packaging…").font(.callout).foregroundStyle(.secondary)
            }
        } else if label == "Regenerate" {
            Button { store.generateHandoff(for: session) } label: {
                Label(label, systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SoftButtonStyle())
        } else {
            Button { store.generateHandoff(for: session) } label: {
                Label(label, systemImage: "shippingbox")
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func section<Content: View>(label: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                sectionLabel(label)
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            content()
        }
    }

    /// A document-style, monospaced, scrollable preview of file content that WOULD be written.
    private func fileBox(_ text: String, maxHeight: CGFloat) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: maxHeight)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    /// A compact, scrollable unified-diff of `old` → `new`: added lines get a green "+" gutter and
    /// tint, removed lines a coral "-", and unchanged context is dimmed and collapsed to a few lines
    /// around each change. A brand-new file is shown entirely as additions under a "New file" strip.
    private func diffBox(old: String, new: String, isNewFile: Bool, maxHeight: CGFloat) -> some View {
        let rows = HandoffCard.diffRows(old: old, new: new)
        return VStack(alignment: .leading, spacing: 0) {
            if isNewFile {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.running)
                    Text("New file")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.running)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.running.opacity(0.08))
                Divider().overlay(Theme.border)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        switch row.content {
                        case .line(let line): diffLineRow(line)
                        case .gap(let hidden): diffGapRow(hidden)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: maxHeight)
        }
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func diffLineRow(_ line: HandoffService.DiffLine) -> some View {
        let style = diffLineStyle(line.kind)
        return HStack(alignment: .top, spacing: 8) {
            Text(style.gutter)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(style.gutterColor)
                .frame(width: 8, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(style.textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.bg)
    }

    private func diffLineStyle(_ kind: HandoffService.DiffLine.Kind)
        -> (gutter: String, gutterColor: Color, bg: Color, textColor: Color) {
        switch kind {
        case .added:   return ("+", Theme.running, Theme.running.opacity(0.13), .primary)
        case .removed: return ("-", Theme.coral, Theme.coral.opacity(0.10), .secondary)
        case .context: return (" ", .clear, .clear, .secondary)
        }
    }

    private func diffGapRow(_ hidden: Int) -> some View {
        HStack(spacing: 8) {
            Text("⋯")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 8, alignment: .leading)
            Text("\(hidden) unchanged line\(hidden == 1 ? "" : "s")")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    /// One row of the rendered diff: either a real diff line or a collapsed-context gap marker.
    private struct DiffDisplayRow: Identifiable {
        enum Content { case line(HandoffService.DiffLine); case gap(Int) }
        let id: Int
        let content: Content
    }

    /// Turns a full line diff into display rows, collapsing runs of unchanged context to `context`
    /// lines around each change (replacing the hidden middle with a single gap marker). A pure
    /// insertion (all `.added`, e.g. a new file) keeps every line — nothing to collapse.
    private static func diffRows(old: String, new: String, context: Int = 3) -> [DiffDisplayRow] {
        let diff = HandoffService.unifiedDiff(old: old, new: new)
        guard !diff.isEmpty else { return [] }

        // Mark which lines to keep: every change, plus `context` lines on either side.
        var keep = Array(repeating: false, count: diff.count)
        for (i, d) in diff.enumerated() where d.kind != .context {
            for k in max(0, i - context)...min(diff.count - 1, i + context) { keep[k] = true }
        }

        var rows: [DiffDisplayRow] = []
        var id = 0
        var i = 0
        while i < diff.count {
            if keep[i] {
                rows.append(DiffDisplayRow(id: id, content: .line(diff[i]))); id += 1; i += 1
            } else {
                var j = i
                while j < diff.count && !keep[j] { j += 1 }
                rows.append(DiffDisplayRow(id: id, content: .gap(j - i))); id += 1
                i = j
            }
        }
        return rows
    }

    /// KICKSTART — reuses the Pickup Brief's NEXT PROMPT terminal-block styling.
    private func kickstartBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("KICKSTART PROMPT")
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.coralHi)
                    .padding(.top, 2)
                Text(text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xEDE6DF))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))

            Button {
                ResumeService.copy(text)
                copiedKickstart = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copiedKickstart = false
                }
            } label: {
                Label(copiedKickstart ? "Copied to clipboard" : "Copy kickstart prompt",
                      systemImage: copiedKickstart ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(GradientButtonStyle())
        }
    }
}

/// Per-model cost chips for the per-session Usage card (top few models).
struct FlowChips: View {
    let models: [ModelStat]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(models.prefix(3)) { m in
                HStack(spacing: 5) {
                    Text(m.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(Fmt.cost(m.cost))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.coralTint.opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.coral.opacity(0.22), lineWidth: 1))
            }
        }
    }
}
