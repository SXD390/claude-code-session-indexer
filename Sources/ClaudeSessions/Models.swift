import Foundation

/// Metadata for one Claude Code session, parsed from its .jsonl transcript.
struct SessionMeta: Identifiable, Codable, Hashable {
    var id: String { sessionId }

    let sessionId: String
    let transcriptPath: String
    /// Encoded project directory name under ~/.claude/projects (grouping key).
    let projectKey: String

    var customTitle: String?
    var aiTitle: String?
    var firstPrompt: String?
    /// Real project path taken from message lines (more reliable than decoding the dir name).
    var cwd: String?
    var gitBranch: String?
    var model: String?
    var cliVersion: String?

    var createdAt: Date?
    var lastActivityAt: Date?
    var userMessageCount: Int = 0
    var assistantMessageCount: Int = 0
    var fileSize: Int64 = 0

    // Cache validation
    var fileModifiedAt: Date?

    /// Best available display title: user-set name > AI title > first prompt > id.
    var displayTitle: String {
        if let t = customTitle, !t.isEmpty { return t }
        if let t = aiTitle, !t.isEmpty { return t }
        if let p = firstPrompt, !p.isEmpty {
            let line = p.split(separator: "\n").first.map(String.init) ?? p
            return line.count > 80 ? String(line.prefix(80)) + "…" : line
        }
        return String(sessionId.prefix(8))
    }

    var hasCustomName: Bool { customTitle?.isEmpty == false }

    var projectDisplayName: String {
        if let cwd, !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return projectKey
    }

    /// Shell command that resumes this session.
    var resumeCommand: String {
        if let cwd, !cwd.isEmpty {
            return "cd \"\(cwd)\" && claude --resume \(sessionId)"
        }
        return "claude --resume \(sessionId)"
    }

    var isEmpty: Bool { userMessageCount == 0 && customTitle == nil }
}

/// A project grouping (one encoded directory under ~/.claude/projects).
struct ProjectGroup: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let displayName: String
    let path: String?
    let sessionCount: Int
}

/// A live session read from ~/.claude/sessions/*.json whose process is still running.
struct ActiveSession: Codable {
    let sessionId: String
    let pid: Int32
    let name: String?
    let status: String?
    let cwd: String?
}

/// One message extracted for the conversation preview.
struct PreviewMessage: Identifiable, Hashable {
    let id: Int
    let role: String   // "user" | "assistant"
    let text: String
    let timestamp: Date?
}

/// A persisted AI-generated summary.
struct StoredSummary: Codable {
    let text: String
    let generatedAt: Date
    /// Last-activity date of the session when the summary was generated,
    /// so we can tell when a summary is stale.
    let sessionLastActivity: Date?
}

enum SortOrder: String, CaseIterable, Identifiable {
    case lastActivity = "Last Activity"
    case created = "Date Created"
    case messages = "Most Messages"
    var id: String { rawValue }
}

enum SidebarItem: Hashable {
    case all
    case named
    case active
    case project(String)  // projectKey
}
