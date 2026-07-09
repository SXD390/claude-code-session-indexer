import Foundation

/// Generates "Pickup Briefs" via `claude -p` (headless), mirroring SummaryService's
/// discovery / cwd / timeout, then parses the STATE / OPEN / NEXT PROMPT sections.
enum BriefService {

    struct ParsedBrief {
        let state: String
        let open: [String]
        let nextPrompt: String
        let raw: String
    }

    enum BriefError: LocalizedError {
        case claudeNotFound
        case emptyTranscript
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound: return "Couldn't find the `claude` CLI on your PATH."
            case .emptyTranscript: return "This session has no conversation content to brief."
            case .processFailed(let msg): return msg.isEmpty ? "claude -p failed." : msg
            }
        }
    }

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

    private static let instruction = """
    The stdin contains the tail of a Claude Code session transcript. Produce a pickup brief \
    for resuming this work, in exactly this format:
    STATE: 2-3 plain sentences on where the work stands (what was completed, what was in progress \
    when the session ended).
    OPEN: up to 4 bullets (- ) of unresolved threads, known bugs, or explicitly deferred TODOs. \
    Write 'none' if clean.
    NEXT PROMPT: a single ready-to-paste prompt (2-5 sentences, imperative, self-contained — assume \
    the resumed session has full prior context) that would continue the work most productively.
    """

    static func generate(session: SessionMeta) async -> Result<ParsedBrief, BriefError> {
        guard let claude = claudePath else { return .failure(.claudeNotFound) }

        let excerpt = buildExcerpt(session: session)
        guard !excerpt.isEmpty else { return .failure(.emptyTranscript) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["-p", instruction, "--model", "sonnet"]
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
        return .success(parse(out))
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
        let (tail, lastAssistant) = TranscriptScanner.extractBriefTail(url: url, limit: 30)
        guard !tail.isEmpty else { return "" }

        var parts: [String] = []
        parts.append("Project: \(session.projectDisplayName)")
        if let t = session.customTitle { parts.append("User-assigned session name: \(t)") }
        if let t = session.aiTitle { parts.append("Session title: \(t)") }
        if let p = session.firstPrompt { parts.append("First prompt: " + String(p.prefix(500))) }
        parts.append("--- LAST \(tail.count) MESSAGES ---")

        var budget = 14_000
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
            parts.append(paths.prefix(15).joined(separator: "\n"))
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

    static func parse(_ raw: String) -> ParsedBrief {
        var state = ""
        var open: [String] = []
        var nextLines: [String] = []
        var section = 0   // 0 none, 1 state, 2 open, 3 next

        func stripMarkers(_ s: String) -> String {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "*#> ").union(.whitespaces))
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let cleaned = stripMarkers(line)
            let upper = cleaned.uppercased()

            if upper.hasPrefix("STATE:") {
                section = 1
                let rest = String(cleaned.dropFirst("STATE:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { state = rest }
                continue
            }
            if upper.hasPrefix("OPEN:") {
                section = 2
                let rest = String(cleaned.dropFirst("OPEN:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty && rest.lowercased() != "none" { open.append(rest) }
                continue
            }
            if upper.hasPrefix("NEXT PROMPT:") {
                section = 3
                let rest = String(cleaned.dropFirst("NEXT PROMPT:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { nextLines.append(rest) }
                continue
            }

            switch section {
            case 1:
                if !cleaned.isEmpty { state += (state.isEmpty ? "" : " ") + cleaned }
            case 2:
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("-") || t.hasPrefix("•") || t.hasPrefix("*") {
                    let bullet = stripMarkers(String(t.dropFirst()))
                    if !bullet.isEmpty { open.append(bullet) }
                } else if !cleaned.isEmpty {
                    open.append(cleaned)
                }
            case 3:
                // Preserve the prompt's own line breaks.
                if !nextLines.isEmpty || !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    nextLines.append(line)
                }
            default:
                break
            }
        }

        // "none" sentinel → empty list.
        if open.count == 1, open[0].lowercased().hasPrefix("none") { open = [] }
        open = open.filter { !$0.isEmpty }.prefix(4).map { $0 }

        let nextPrompt = nextLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalState = state.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback: if the model ignored the format, keep the raw text as the state.
        if finalState.isEmpty && nextPrompt.isEmpty && open.isEmpty {
            return ParsedBrief(state: raw.trimmingCharacters(in: .whitespacesAndNewlines), open: [], nextPrompt: "", raw: raw)
        }
        return ParsedBrief(state: finalState, open: open, nextPrompt: nextPrompt, raw: raw)
    }
}
