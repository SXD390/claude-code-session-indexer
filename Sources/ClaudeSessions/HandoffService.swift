import Foundation

/// Generates a "Handoff" package via `claude -p` (headless), mirroring BriefService's
/// discovery / cwd / timeout, then parses the PROGRESS / CLAUDE / KICKSTART sections.
///
/// The parsed package can then be written INTO the session's project directory
/// (`session.cwd`) so a brand-new Claude Code session can pick up the old work.
/// Generation never touches disk — writing is a separate, explicit step.
enum HandoffService {

    struct ParsedHandoff {
        /// Markdown body for a dated progress section (starts with "## <date> — <title>").
        let progress: String
        /// Durable project knowledge for a future session, or nil if the model said NONE.
        let claude: String?
        /// A single ready-to-paste kickstart prompt.
        let kickstart: String
        let raw: String
    }

    enum HandoffError: LocalizedError {
        case claudeNotFound
        case emptyTranscript
        case processFailed(String)
        case noProjectDir
        case projectDirMissing(String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound: return "Couldn't find the `claude` CLI on your PATH."
            case .emptyTranscript: return "This session has no conversation content to package."
            case .processFailed(let msg): return msg.isEmpty ? "claude -p failed." : msg
            case .noProjectDir: return "This session has no known project directory (cwd) to write into."
            case .projectDirMissing(let path): return "Project directory no longer exists: \(path)"
            }
        }
    }

    // MARK: - CLAUDE.md marker block

    static let claudeStartMarker = "<!-- session-indexer:handoff:start -->"
    static let claudeEndMarker = "<!-- session-indexer:handoff:end -->"

    private static let claudePath: String? = {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        } catch { return nil }
    }()

    // MARK: - Instruction

    private static func instruction(date: String, title: String) -> String {
        """
        The stdin contains the tail of a Claude Code session transcript. Produce a HANDOFF \
        package so a brand-new Claude Code session (with NO prior context) can continue this work. \
        Today's date is \(date). The session's working title is "\(title)".

        Output EXACTLY these delimited sections, in this order, and nothing outside them \
        (no preamble, no code fences):

        ===PROGRESS===
        A dated progress section in Markdown. Its first line MUST be exactly:
        ## \(date) — \(title)
        Then these bold subsections, each on its own line, each followed by bullet lines that \
        start with "- ":
        **Done** — what was completed this session
        **In progress** — what was mid-flight when the session ended
        **Open threads** — unresolved TODOs, known bugs, or explicitly deferred work
        **Key decisions** — notable choices made and why
        **Files touched** — one bullet per file path
        **How to verify** — 1 to 3 bullets with concrete commands or checks (use real commands if \
        the transcript reveals them)
        Omit a subsection's bullets only if truly nothing applies, but keep its heading.
        ===CLAUDE===
        DURABLE project knowledge a FUTURE Claude session should know, in Markdown: build / run / \
        test commands observed in the transcript, project structure notes, conventions, and gotchas. \
        Do NOT put session-specific status here. If the transcript reveals nothing durable, output \
        the single word NONE (nothing else).
        ===KICKSTART===
        A single ready-to-paste prompt, 3 to 6 sentences. Tell the new session to read PROGRESS.md \
        (and CLAUDE.md if present) in this directory, state the immediate goal drawn from the open \
        threads, and say how to verify when the task is done.
        ===END===
        """
    }

    // MARK: - Generate

    static func generate(session: SessionMeta) async -> Result<ParsedHandoff, HandoffError> {
        guard let claude = claudePath else { return .failure(.claudeNotFound) }

        let excerpt = buildExcerpt(session: session)
        guard !excerpt.isEmpty else { return .failure(.emptyTranscript) }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        let title = handoffTitle(for: session)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["-p", instruction(date: today, title: title), "--model", "sonnet"]
        proc.currentDirectoryURL = SessionStore.summaryWorkDir

        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CODE_DISABLE_AUTOUPDATE"] = "1"
        proc.environment = env

        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do { try proc.run() } catch { return .failure(.processFailed(error.localizedDescription)) }

        stdinPipe.fileHandleForWriting.write(Data(excerpt.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        async let outData = readAll(stdoutPipe)
        async let errData = readAll(stderrPipe)

        let deadline = Date().addingTimeInterval(180)
        while proc.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if proc.isRunning {
            proc.terminate()
            return .failure(.processFailed("Timed out after 3 minutes."))
        }

        let out = String(decoding: await outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(decoding: await errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if proc.terminationStatus != 0 {
            return .failure(.processFailed(err.isEmpty ? "claude exited with status \(proc.terminationStatus)" : String(err.prefix(300))))
        }
        guard !out.isEmpty else { return .failure(.processFailed("claude returned no output.")) }
        return .success(parse(out, date: today, title: title))
    }

    private static func handoffTitle(for session: SessionMeta) -> String {
        let t = session.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 80 ? String(t.prefix(80)) + "…" : t
    }

    private static func readAll(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }

    // MARK: - Excerpt

    private static func buildExcerpt(session: SessionMeta) -> String {
        let url = URL(fileURLWithPath: session.transcriptPath)
        let (tail, lastAssistant) = TranscriptScanner.extractBriefTail(url: url, limit: 50)
        guard !tail.isEmpty else { return "" }

        var parts: [String] = []
        parts.append("Project: \(session.projectDisplayName)")
        if let t = session.customTitle { parts.append("User-assigned session name: \(t)") }
        if let t = session.aiTitle { parts.append("Session title: \(t)") }
        if let p = session.firstPrompt { parts.append("First prompt: " + String(p.prefix(500))) }
        parts.append("--- LAST \(tail.count) MESSAGES ---")

        var budget = 16_000
        for m in tail {
            let label = m.role == "user" ? "USER" : "CLAUDE"
            let snippet = "\(label): " + String(m.text.prefix(500))
            budget -= snippet.count
            if budget < 0 { break }
            parts.append(snippet)
        }

        let paths = filePaths(in: lastAssistant ?? "")
        if !paths.isEmpty {
            parts.append("--- FILES TOUCHED IN LAST MESSAGE ---")
            parts.append(paths.prefix(20).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }

    /// Path-like tokens (contain a slash + an extension-ish tail) from a message.
    private static func filePaths(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?:[A-Za-z0-9_.\-]+/)+[A-Za-z0-9_.\-]+"#) else { return [] }
        let ns = text as NSString
        var out: [String] = []
        var seen = Set<String>()
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let s = ns.substring(with: m.range)
            guard s.contains("."), s.count <= 120 else { continue }
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    // MARK: - Parse

    /// Splits the model output on the ===PROGRESS===/===CLAUDE===/===KICKSTART===/===END===
    /// markers. `date`/`title` are used only to synthesize a fallback heading if the model
    /// omitted the PROGRESS section entirely.
    static func parse(_ raw: String, date: String = "", title: String = "") -> ParsedHandoff {
        func section(from start: String, to end: String) -> String {
            guard let s = raw.range(of: start) else { return "" }
            let endLower = raw.range(of: end, range: s.upperBound..<raw.endIndex)?.lowerBound ?? raw.endIndex
            return String(raw[s.upperBound..<endLower]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var progress = section(from: "===PROGRESS===", to: "===CLAUDE===")
        let claudeRaw = section(from: "===CLAUDE===", to: "===KICKSTART===")
        let kickstart = section(from: "===KICKSTART===", to: "===END===")

        // NONE sentinel (tolerant of trailing punctuation / markdown) → no durable knowledge.
        let claudeFlat = claudeRaw
            .trimmingCharacters(in: CharacterSet(charactersIn: " .*#\n\t"))
            .uppercased()
        let claude: String? = (claudeRaw.isEmpty || claudeFlat == "NONE") ? nil : claudeRaw

        // Fallback: model ignored the format entirely — keep the whole output as the progress
        // body under a synthesized heading so the user still gets something usable.
        if progress.isEmpty && claude == nil && kickstart.isEmpty {
            let heading = date.isEmpty ? "## Handoff" : "## \(date) — \(title)"
            let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            progress = body.isEmpty ? heading : "\(heading)\n\n\(body)"
        }

        return ParsedHandoff(progress: progress, claude: claude, kickstart: kickstart, raw: raw)
    }

    // MARK: - Writing (SAFETY CRITICAL)

    struct WriteRequest {
        let session: SessionMeta
        /// Dated PROGRESS.md section body (as parsed).
        let progressSection: String
        /// Durable CLAUDE.md content; nil when the model returned NONE.
        let claudeContent: String?
        /// Whether the user opted to also write/update CLAUDE.md.
        let includeClaudeMd: Bool
    }

    /// Validates the target directory and writes PROGRESS.md (and optionally CLAUDE.md)
    /// INSIDE `session.cwd` only. Returns the URLs actually written. Never deletes content.
    @discardableResult
    static func writeToProject(_ req: WriteRequest) throws -> [URL] {
        guard let cwdPath = req.session.cwd, !cwdPath.isEmpty else {
            throw HandoffError.noProjectDir
        }
        // SECURITY: cwd is untrusted (transcript-supplied). Require an ABSOLUTE path so it can
        // never be resolved relative to the process working directory, and require it to be an
        // EXISTING directory so the write is refused (not silently misdirected) when the project
        // is gone. Combined with the hardcoded PROGRESS.md/CLAUDE.md filenames below, this bounds
        // every write to two known files inside a real directory the session actually ran in.
        guard cwdPath.hasPrefix("/") else {
            throw HandoffError.projectDirMissing(cwdPath)
        }
        let dir = URL(fileURLWithPath: cwdPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw HandoffError.projectDirMissing(cwdPath)
        }

        var written: [URL] = []
        written.append(try writeProgress(
            dir: dir,
            projectName: req.session.projectDisplayName,
            section: req.progressSection))

        if req.includeClaudeMd, let content = req.claudeContent, !content.isEmpty {
            written.append(try writeClaudeMd(dir: dir, content: content))
        }
        return written
    }

    /// PROGRESS.md: create fresh, or insert the new dated section directly after a leading
    /// "# " title (else at the very top), preserving everything below. Never deletes content.
    ///
    /// The on-disk merge is delegated to the pure `mergedProgress` below so the write and the UI
    /// diff/copy previews compute the EXACT same bytes and can never diverge.
    static func writeProgress(dir: URL, projectName: String, section: String) throws -> URL {
        let url = dir.appendingPathComponent("PROGRESS.md")
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let out = mergedProgress(existing: existing, projectName: projectName, section: section)
        try out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// PURE (no file I/O): computes the resulting PROGRESS.md contents. `existing` is the current
    /// on-disk text (nil / empty ⇒ create fresh). This is the single source of truth shared by the
    /// writer, the diff preview, and the "Copy PROGRESS.md" action.
    static func mergedProgress(existing: String?, projectName: String, section: String) -> String {
        let sectionTrimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)

        var out: String
        if let existing = existing, !existing.isEmpty {
            let lines = existing.components(separatedBy: "\n")
            if let first = lines.first, first.hasPrefix("# ") {
                // Keep the title line, insert the new section, then the rest (minus any
                // leading blank lines that used to follow the title).
                var below = Array(lines.dropFirst())
                while let f = below.first, f.trimmingCharacters(in: .whitespaces).isEmpty {
                    below.removeFirst()
                }
                let belowStr = below.joined(separator: "\n")
                out = first + "\n\n" + sectionTrimmed + "\n\n" + belowStr
            } else {
                out = sectionTrimmed + "\n\n" + existing
            }
        } else {
            out = "# Progress — \(projectName)\n\n" + sectionTrimmed
        }

        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    /// CLAUDE.md: create with only the delimited block, or replace an existing marked block,
    /// or append a fresh block. Never overwrites the user's own content outside the markers.
    ///
    /// The on-disk merge is delegated to the pure `mergedClaude` below so the write and the UI
    /// diff/copy previews compute the EXACT same bytes and can never diverge.
    static func writeClaudeMd(dir: URL, content: String) throws -> URL {
        let url = dir.appendingPathComponent("CLAUDE.md")
        let block = markerBlock(content: content)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let out = mergedClaude(existing: existing, block: block)
        try out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// PURE (no file I/O): computes the resulting CLAUDE.md contents. `existing` is the current
    /// on-disk text (nil / empty ⇒ create block-only); `block` is a fully-formed marker block from
    /// `markerBlock(content:)`. Single source of truth for the writer, diff, and copy action.
    static func mergedClaude(existing: String?, block: String) -> String {
        var out: String
        if var existing = existing, !existing.isEmpty {
            if let start = existing.range(of: claudeStartMarker),
               let end = existing.range(of: claudeEndMarker),
               start.lowerBound < end.lowerBound {
                existing.replaceSubrange(start.lowerBound..<end.upperBound, with: block)
                out = existing
            } else {
                let sep = existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
                out = existing + sep + block
            }
        } else {
            out = block
        }

        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    static func markerBlock(content: String) -> String {
        // SECURITY: the model's content is influenced by (untrusted) transcript text. If it
        // contained our own start/end marker comments, a later marker-block replacement in
        // writeClaudeMd would match the WRONG delimiters and could orphan or clobber text. Strip
        // any embedded markers so the managed block always has exactly one start and one end.
        let body = content
            .replacingOccurrences(of: claudeStartMarker, with: "")
            .replacingOccurrences(of: claudeEndMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(claudeStartMarker)\n\(body)\n\(claudeEndMarker)"
    }

    // MARK: - Line diff (dependency-free)

    /// One line of a unified diff. `.added` lines are what the merge introduces (a new dated
    /// PROGRESS.md section or a fresh CLAUDE.md marker block); `.removed` lines are dropped from
    /// the old file; `.context` lines are unchanged and shown (dimmed) for orientation.
    struct DiffLine: Equatable {
        enum Kind { case context, added, removed }
        let kind: Kind
        let text: String
    }

    /// PURE line-level diff of `old` → `new` via LCS. Emits an in-order sequence of context /
    /// removed / added lines. The common Handoff case is a pure insertion (a new section or block),
    /// which surfaces as a run of `.added` lines flanked by `.context`. Dependency-free.
    static func unifiedDiff(old: String, new: String) -> [DiffLine] {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)
        let n = oldLines.count, m = newLines.count

        if n == 0 { return newLines.map { DiffLine(kind: .added, text: $0) } }
        if m == 0 { return oldLines.map { DiffLine(kind: .removed, text: $0) } }

        // LCS length table: dp[i][j] = LCS(oldLines[i...], newLines[j...]).
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = oldLines[i] == newLines[j]
                    ? dp[i + 1][j + 1] + 1
                    : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var out: [DiffLine] = []
        var i = 0, j = 0
        while i < n && j < m {
            if oldLines[i] == newLines[j] {
                out.append(DiffLine(kind: .context, text: oldLines[i])); i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                out.append(DiffLine(kind: .removed, text: oldLines[i])); i += 1
            } else {
                out.append(DiffLine(kind: .added, text: newLines[j])); j += 1
            }
        }
        while i < n { out.append(DiffLine(kind: .removed, text: oldLines[i])); i += 1 }
        while j < m { out.append(DiffLine(kind: .added, text: newLines[j])); j += 1 }
        return out
    }

    /// Splits into lines on "\n", dropping a single trailing empty element so a file that ends in a
    /// newline is not diffed as having an extra blank line.
    private static func splitLines(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var lines = s.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
