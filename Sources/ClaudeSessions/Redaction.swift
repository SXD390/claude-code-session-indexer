import Foundation

/// Redacts high-confidence secrets from transcript text.
///
/// Claude Code sessions routinely contain `.env` dumps, API keys, and tokens that
/// the user pasted or that a tool printed. This app both *displays* that text and
/// *feeds excerpts to `claude -p`* (whose output is written into PROGRESS.md /
/// CLAUDE.md), so secrets are scrubbed at both points.
///
/// Patterns are deliberately conservative — vendor-prefixed keys and labelled
/// `NAME=value` assignments — so ordinary prose and code are left untouched. This
/// is defense-in-depth, not a guarantee; the tool still only ever reads the user's
/// own local files.
///
/// Kept in lockstep with `redactSecrets()` in web/server.js — change both together.
enum Redaction {
    static let placeholder = "[REDACTED]"

    // (pattern, options) pairs. Order doesn't matter; all are applied.
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            // Private key blocks (multi-line).
            "-----BEGIN[ A-Z]*PRIVATE KEY-----[\\s\\S]*?-----END[ A-Z]*PRIVATE KEY-----",
            // Anthropic / OpenAI style: sk-..., sk-ant-...
            "\\bsk-[A-Za-z0-9_-]{16,}\\b",
            // GitHub tokens + fine-grained PATs.
            "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b",
            "\\bgithub_pat_[A-Za-z0-9_]{20,}\\b",
            // AWS access key id.
            "\\bA(?:KIA|SIA)[0-9A-Z]{16}\\b",
            // Google API key.
            "\\bAIza[0-9A-Za-z_-]{35}\\b",
            // Slack tokens.
            "\\bxox[baprs]-[A-Za-z0-9-]{10,}\\b",
            // JWTs (three base64url segments).
            "\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\b",
            // Bearer <token>
            "(?i)\\bBearer\\s+[A-Za-z0-9._~+/=-]{20,}",
            // Labelled assignments: SECRET/TOKEN/PASSWORD/API_KEY/... = value
            // Redacts only the value, keeps the key name.
            "(?i)((?:api[_-]?key|secret|token|password|passwd|private[_-]?key|access[_-]?key|client[_-]?secret|auth[_-]?token|credential)\\s*[=:]\\s*)[\"']?[^\\s\"'#]{6,}",
        ]
        return raw.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators])
        }
    }()

    static func redact(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = s
        for (i, re) in patterns.enumerated() {
            let range = NSRange(out.startIndex..., in: out)
            // The labelled-assignment pattern (last) keeps group 1 (the key + separator)
            // and replaces the value; everything else replaces the whole match.
            let template = (i == patterns.count - 1) ? "$1\(placeholder)" : placeholder
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: template)
        }
        return out
    }
}
