import Foundation

/// Generates session summaries by shelling out to `claude -p` (headless mode).
enum SummaryService {

    enum SummaryError: LocalizedError {
        case claudeNotFound
        case emptyTranscript
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:
                return "Couldn't find the `claude` CLI on your PATH."
            case .emptyTranscript:
                return "This session has no conversation content to summarize."
            case .processFailed(let msg):
                return msg.isEmpty ? "claude -p failed." : msg
            }
        }
    }

    /// Resolved once per app run via a login shell so we get the user's real PATH.
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
        } catch {
            return nil
        }
    }()

    static func summarize(session: SessionMeta) async -> Result<String, SummaryError> {
        guard let claude = claudePath else { return .failure(.claudeNotFound) }

        let excerpt = buildExcerpt(session: session)
        guard !excerpt.isEmpty else { return .failure(.emptyTranscript) }

        let instruction = """
        The stdin contains an excerpt of a Claude Code CLI coding session transcript. \
        Write a summary of the session: first 1-2 plain sentences stating the goal and what was accomplished, \
        then up to 3 short bullet points (starting with "- ") of key outcomes or decisions. \
        No preamble, no headers, under 110 words total.
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["-p", instruction, "--model", "haiku"]
        proc.currentDirectoryURL = SessionStore.summaryWorkDir

        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CODE_DISABLE_AUTOUPDATE"] = "1"
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            return .failure(.processFailed(error.localizedDescription))
        }

        stdinPipe.fileHandleForWriting.write(Data(excerpt.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        // Read pipes off the waiting thread to avoid deadlock on large output.
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
        guard !out.isEmpty else {
            return .failure(.processFailed("claude returned no output."))
        }
        return .success(out)
    }

    private static func readAll(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }

    /// Builds a compact transcript excerpt: titles + user prompts + closing assistant text.
    private static func buildExcerpt(session: SessionMeta) -> String {
        let url = URL(fileURLWithPath: session.transcriptPath)
        let messages = TranscriptScanner.extractPreview(url: url, limit: 400)
        guard !messages.isEmpty else { return "" }

        var parts: [String] = []
        parts.append("Project: \(session.projectDisplayName)")
        if let t = session.customTitle { parts.append("User-assigned session name: \(t)") }
        if let t = session.aiTitle { parts.append("Session title: \(t)") }
        parts.append("---")

        var budget = 14_000
        let userMessages = messages.filter { $0.role == "user" }
        for m in userMessages.prefix(50) {
            let snippet = "USER: " + m.text.prefix(400)
            budget -= snippet.count
            if budget < 2_000 { break }
            parts.append(String(snippet))
        }

        // Close with the tail of the conversation so the summary reflects the outcome.
        if let lastAssistant = messages.last(where: { $0.role == "assistant" }) {
            parts.append("---")
            parts.append("FINAL ASSISTANT MESSAGE: " + lastAssistant.text.prefix(1500))
        }
        return parts.joined(separator: "\n")
    }
}
