import Foundation

/// Parses Claude Code .jsonl transcripts under ~/.claude/projects.
///
/// Transcripts are line-delimited JSON. We avoid JSON-decoding every line:
/// cheap substring checks decide which lines are worth parsing, and
/// timestamps are pulled out with plain string scans.
enum TranscriptScanner {

    /// CSI_CLAUDE_DIR points the indexer at an alternate data root (demos, tests).
    static var claudeRoot: URL {
        if let override = ProcessInfo.processInfo.environment["CSI_CLAUDE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    static var projectsDir: URL {
        claudeRoot.appendingPathComponent("projects")
    }

    static var liveSessionsDir: URL {
        claudeRoot.appendingPathComponent("sessions")
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoParser.date(from: s) ?? isoParserNoFraction.date(from: s)
    }

    /// Lists every transcript file with its mtime/size, without reading contents.
    static func listTranscripts(excludingProjectPaths excluded: Set<String>) -> [(url: URL, projectKey: String, mtime: Date, size: Int64)] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [(URL, String, Date, Int64)] = []
        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let key = dir.lastPathComponent
            if excluded.contains(key) { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                // Session transcripts are named by UUID; skip anything else (agent files, etc.)
                let stem = file.deletingPathExtension().lastPathComponent
                guard UUID(uuidString: stem) != nil else { continue }
                let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                result.append((file, key, vals?.contentModificationDate ?? .distantPast, Int64(vals?.fileSize ?? 0)))
            }
        }
        return result
    }

    /// Full parse of one transcript into SessionMeta.
    static func parseTranscript(url: URL, projectKey: String, mtime: Date, size: Int64) -> SessionMeta {
        let sessionId = url.deletingPathExtension().lastPathComponent
        var meta = SessionMeta(sessionId: sessionId, transcriptPath: url.path, projectKey: projectKey)
        meta.fileSize = size
        meta.fileModifiedAt = mtime

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return meta }
        let content = String(decoding: data, as: UTF8.self)

        var firstTimestamp: String?
        var lastTimestamp: String?

        for lineSub in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = lineSub

            if line.contains("\"timestamp\":\"") {
                if let ts = extractString(from: line, key: "timestamp") {
                    if firstTimestamp == nil { firstTimestamp = ts }
                    lastTimestamp = ts
                }
            }

            if line.contains("\"type\":\"custom-title\"") {
                if let obj = decode(line), let t = obj["customTitle"] as? String {
                    meta.customTitle = t
                }
                continue
            }
            if line.contains("\"type\":\"ai-title\"") {
                if let obj = decode(line), let t = obj["aiTitle"] as? String {
                    meta.aiTitle = t
                }
                continue
            }

            // Subagent (sidechain) traffic isn't part of the user's conversation.
            if line.contains("\"isSidechain\":true") { continue }

            if line.contains("\"type\":\"assistant\"") {
                meta.assistantMessageCount += 1
                if meta.model == nil, line.contains("\"model\":\""),
                   let m = extractString(from: line, key: "model") {
                    meta.model = m
                }
                continue
            }

            if line.contains("\"type\":\"user\"") {
                // Skip meta lines (command wrappers, caveats) and tool results.
                if line.contains("\"isMeta\":true") || line.contains("\"tool_result\"") { continue }
                meta.userMessageCount += 1

                if meta.cwd == nil, let c = extractString(from: line, key: "cwd") {
                    meta.cwd = c
                }
                if meta.gitBranch == nil, let b = extractString(from: line, key: "gitBranch"), !b.isEmpty {
                    meta.gitBranch = b
                }
                if meta.cliVersion == nil, let v = extractString(from: line, key: "version") {
                    meta.cliVersion = v
                }
                if meta.firstPrompt == nil, let obj = decode(line),
                   let text = userText(from: obj), isRealPrompt(text) {
                    meta.firstPrompt = String(text.prefix(600))
                }
                continue
            }
        }

        if let ts = firstTimestamp { meta.createdAt = parseDate(ts) }
        if let ts = lastTimestamp { meta.lastActivityAt = parseDate(ts) }
        if meta.lastActivityAt == nil { meta.lastActivityAt = mtime }
        return meta
    }

    /// Extracts user + assistant text messages for the detail-pane preview.
    static func extractPreview(url: URL, limit: Int = 400) -> [PreviewMessage] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let content = String(decoding: data, as: UTF8.self)
        var messages: [PreviewMessage] = []
        var idx = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            if messages.count >= limit { break }
            if line.contains("\"isSidechain\":true") { continue }
            let isUser = line.contains("\"type\":\"user\"")
            let isAssistant = line.contains("\"type\":\"assistant\"")
            guard isUser || isAssistant else { continue }
            if isUser && (line.contains("\"isMeta\":true") || line.contains("\"tool_result\"")) { continue }

            guard let obj = decode(line) else { continue }
            let ts = (obj["timestamp"] as? String).flatMap(parseDate)

            if isUser {
                if let text = userText(from: obj), isRealPrompt(text) {
                    messages.append(PreviewMessage(id: idx, role: "user", text: Redaction.redact(String(text.prefix(1500))), timestamp: ts))
                    idx += 1
                }
            } else {
                if let text = assistantText(from: obj), !text.isEmpty {
                    messages.append(PreviewMessage(id: idx, role: "assistant", text: Redaction.redact(String(text.prefix(1500))), timestamp: ts))
                    idx += 1
                }
            }
        }
        return messages
    }

    /// Reads live-session descriptors and keeps ones whose process is still alive.
    static func activeSessions() -> [String: ActiveSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: liveSessionsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [:] }

        var map: [String: ActiveSession] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = obj["sessionId"] as? String,
                  let pid = (obj["pid"] as? NSNumber)?.int32Value
            else { continue }
            // kill(pid, 0) probes for existence without sending a signal.
            guard kill(pid, 0) == 0 else { continue }
            map[sessionId] = ActiveSession(
                sessionId: sessionId,
                pid: pid,
                name: obj["name"] as? String,
                status: obj["status"] as? String,
                cwd: obj["cwd"] as? String
            )
        }
        return map
    }

    // MARK: - Helpers

    private static func decode(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Pulls "key":"value" out of a JSON line with a plain string scan
    /// (unescapes the common backslash sequences).
    private static func extractString(from line: Substring, key: String) -> String? {
        let needle = "\"\(key)\":\""
        guard let start = line.range(of: needle)?.upperBound else { return nil }
        var result = ""
        var i = start
        while i < line.endIndex {
            let c = line[i]
            if c == "\\" {
                let next = line.index(after: i)
                guard next < line.endIndex else { break }
                switch line[next] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                default:
                    // Give up on rare escapes (\uXXXX) — fall back to full JSON parse.
                    if let obj = decode(line) { return obj[key] as? String }
                    return result
                }
                i = line.index(after: next)
            } else if c == "\"" {
                return result
            } else {
                result.append(c)
                i = line.index(after: i)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Extracts the human text of a user message (string or content-array form).
    static func userText(from obj: [String: Any]) -> String? {
        guard let message = obj["message"] as? [String: Any] else { return nil }
        if let s = message["content"] as? String { return s }
        if let parts = message["content"] as? [[String: Any]] {
            let texts = parts.compactMap { part -> String? in
                guard part["type"] as? String == "text" else { return nil }
                return part["text"] as? String
            }
            let joined = texts.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    static func assistantText(from obj: [String: Any]) -> String? {
        guard let message = obj["message"] as? [String: Any],
              let parts = message["content"] as? [[String: Any]] else { return nil }
        let texts = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }
        let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// Filters out command wrappers, caveats, and other machine-generated "user" content.
    static func isRealPrompt(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.hasPrefix("<") { return false }          // <command-name>, <local-command-stdout>, caveats…
        if t.hasPrefix("Caveat:") { return false }
        return true
    }
}

// MARK: - Usage extraction (analytics)

/// One assistant API message's token usage, deduped across streaming chunks.
struct RawUsageEvent {
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let timestamp: Date?
}

struct UsageExtraction {
    var events: [RawUsageEvent]     // deduped by message.id → requestId → line
    var allTimestamps: [Date]       // every line carrying a timestamp, ascending
}

/// One raw deep-search match within a transcript (session metadata attached later).
struct RawDeepMatch {
    let role: String                // "user" | "assistant"
    let snippet: String
    let timestamp: Date?
}

extension TranscriptScanner {

    /// Scans a transcript for assistant token-usage messages (INCLUDING sidechains,
    /// per the analytics spec) plus every timestamp (for the heartbeat time metric).
    static func extractUsage(url: URL) -> UsageExtraction {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return UsageExtraction(events: [], allTimestamps: [])
        }
        let content = String(decoding: data, as: UTF8.self)

        var events: [RawUsageEvent] = []
        var timestamps: [Date] = []
        var seen = Set<String>()
        var fallbackCounter = 0

        for lineSub in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = lineSub

            // Heartbeat: collect timestamps from EVERY line (user + assistant + sidechain).
            if line.contains("\"timestamp\":\""),
               let ts = extractString(from: line, key: "timestamp"),
               let d = parseDate(ts) {
                timestamps.append(d)
            }

            // Usage events: assistant lines carrying a usage block. Sidechains INCLUDED.
            guard line.contains("\"type\":\"assistant\""), line.contains("\"usage\"") else { continue }
            guard let obj = decode(line),
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            // Dedup key: message.id → requestId → count-once-per-line.
            let key: String
            if let mid = message["id"] as? String, !mid.isEmpty {
                key = "m:" + mid
            } else if let rid = obj["requestId"] as? String, !rid.isEmpty {
                key = "r:" + rid
            } else {
                fallbackCounter += 1
                key = "l:\(fallbackCounter)"
            }
            guard seen.insert(key).inserted else { continue }

            let model = (message["model"] as? String) ?? "unknown"
            func tok(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
            let ts = (obj["timestamp"] as? String).flatMap(parseDate)

            events.append(RawUsageEvent(
                model: model,
                input: tok("input_tokens"),
                output: tok("output_tokens"),
                cacheRead: tok("cache_read_input_tokens"),
                cacheWrite: tok("cache_creation_input_tokens"),
                timestamp: ts
            ))
        }

        timestamps.sort()
        return UsageExtraction(events: events, allTimestamps: timestamps)
    }

    /// Case-insensitive substring scan over user + assistant text (skips
    /// meta/tool_result/sidechain, matching the preview extraction rules).
    static func deepSearch(url: URL, query: String, perSessionCap: Int = 8) -> [RawDeepMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [] }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let content = String(decoding: data, as: UTF8.self)
        let qLower = q.lowercased()

        var matches: [RawDeepMatch] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            if matches.count >= perSessionCap { break }
            if line.contains("\"isSidechain\":true") { continue }
            let isUser = line.contains("\"type\":\"user\"")
            let isAssistant = line.contains("\"type\":\"assistant\"")
            guard isUser || isAssistant else { continue }
            if isUser && (line.contains("\"isMeta\":true") || line.contains("\"tool_result\"")) { continue }
            // Cheap reject before the JSON decode.
            guard line.lowercased().contains(qLower) else { continue }

            guard let obj = decode(line) else { continue }
            let text: String? = isUser ? userText(from: obj) : assistantText(from: obj)
            guard let t = text else { continue }
            if isUser && !isRealPrompt(t) { continue }
            guard let r = t.range(of: q, options: .caseInsensitive) else { continue }

            let ts = (obj["timestamp"] as? String).flatMap(parseDate)
            matches.append(RawDeepMatch(
                role: isUser ? "user" : "assistant",
                snippet: snippet(t, around: r, pad: 120),
                timestamp: ts
            ))
        }
        return matches
    }

    /// A ±pad-character window around a match, whitespace-collapsed, with ellipses.
    private static func snippet(_ text: String, around range: Range<String.Index>, pad: Int) -> String {
        let start = text.index(range.lowerBound, offsetBy: -pad, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: pad, limitedBy: text.endIndex) ?? text.endIndex
        var s = String(text[start..<end])
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { s = "…" + s }
        if end < text.endIndex { s = s + "…" }
        return Redaction.redact(s)
    }

    /// Extracts the tail of a session for the Pickup Brief pipeline: the last
    /// `limit` user+assistant text messages plus file paths from the final message.
    static func extractBriefTail(url: URL, limit: Int = 30) -> (messages: [PreviewMessage], lastAssistant: String?) {
        let all = extractPreview(url: url, limit: 2000)
        let tail = Array(all.suffix(limit))
        let lastAssistant = all.last(where: { $0.role == "assistant" })?.text
        return (tail, lastAssistant)
    }
}
