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

    /// A session id is trustworthy for use in shell scripts, process arguments, or filenames
    /// ONLY if it is a canonical UUID. Transcript files are named by UUID, so ids are UUIDs by
    /// construction — but any id that reaches an exec-able surface MUST be re-validated here so a
    /// hand-edited cache, a crafted `sessions/*.json` descriptor, or a future code path can never
    /// smuggle shell metacharacters or extra CLI flags. Used by ResumeService and `resumeCommand`.
    static func isValidSessionId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }

    var projectDisplayName: String {
        if let cwd, !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return projectKey
    }

    /// Shell command that resumes this session — shown in the UI and copied to the clipboard for
    /// the user to paste into a terminal. Both the cwd (untrusted, from the transcript) and the
    /// id are single-quoted so that, even when pasted by hand, a crafted cwd such as
    /// `$(rm -rf ~)` or `x";calc;#` is an inert literal rather than an injected command. Double
    /// quotes were unsafe here because the shell still expands `$`, backticks, and `\` inside them.
    var resumeCommand: String {
        let id = Shell.singleQuote(sessionId)
        if let cwd, !cwd.isEmpty {
            return "cd \(Shell.singleQuote(cwd)) && claude --resume \(id)"
        }
        return "claude --resume \(id)"
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

/// A persisted "Pickup Brief" — parsed into its three sections for rendering.
struct StoredBrief: Codable {
    let state: String
    let open: [String]
    let nextPrompt: String
    let generatedAt: Date
    let sessionLastActivity: Date?
    /// Raw model output, kept as a fallback when parsing is imperfect.
    let raw: String
}

/// A persisted "Handoff" package — parsed into the three sections that get written
/// into the session's project directory (PROGRESS.md / CLAUDE.md) plus the kickstart prompt.
struct StoredHandoff: Codable {
    /// Dated PROGRESS.md section body.
    let progress: String
    /// Durable CLAUDE.md knowledge; nil when the model returned NONE.
    let claude: String?
    /// Ready-to-paste kickstart prompt (never written to disk).
    let kickstart: String
    let generatedAt: Date
    let sessionLastActivity: Date?
    /// Raw model output, kept as a fallback when parsing is imperfect.
    let raw: String
}

/// One deep-search hit inside a transcript, resolved with its session's metadata.
struct DeepSearchHit: Identifiable, Hashable {
    let id = UUID()
    let sessionId: String
    let sessionTitle: String
    let projectKey: String
    let projectName: String
    let role: String          // "user" | "assistant"
    let snippet: String
    let timestamp: Date?
}

/// Insights dashboard date-range presets.
enum RangePreset: String, CaseIterable, Identifiable {
    case d7 = "7D"
    case d30 = "30D"
    case d90 = "90D"
    case all = "All"
    case custom = "Custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .d7: return "Last 7 days"
        case .d30: return "Last 30 days"
        case .d90: return "Last 90 days"
        case .all: return "All time"
        case .custom: return "Custom range"
        }
    }

    var days: Int? {
        switch self {
        case .d7: return 7
        case .d30: return 30
        case .d90: return 90
        case .all, .custom: return nil
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case lastActivity = "Last Activity"
    case created = "Date Created"
    case messages = "Most Messages"
    var id: String { rawValue }
}

enum SidebarItem: Hashable {
    case insights
    case all
    case named
    case active
    case project(String)  // projectKey
}
