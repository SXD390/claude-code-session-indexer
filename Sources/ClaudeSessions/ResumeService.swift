import AppKit
import Foundation

/// Clipboard + one-click "resume in Terminal" actions.
enum ResumeService {

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Opens the session in the user's default terminal by writing an executable
    /// .command file and opening it — no Automation permission prompt needed.
    static func resumeInTerminal(session: SessionMeta) {
        let dir = SessionStore.appSupportDir.appendingPathComponent("resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let safeName = session.displayTitle
            .replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .prefix(40)
        let fileName = (safeName.isEmpty ? String(session.sessionId.prefix(8)) : String(safeName)) + ".command"
        let scriptURL = dir.appendingPathComponent(fileName)

        var script = "#!/bin/zsh\n"
        if let cwd = session.cwd, !cwd.isEmpty {
            script += "cd \(shellQuote(cwd)) || exit 1\n"
        }
        script += "exec claude --resume \(session.sessionId)\n"

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
        } catch {
            NSSound.beep()
        }
    }

    static func revealTranscript(session: SessionMeta) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.transcriptPath)])
    }

    static func openProjectInFinder(session: SessionMeta) {
        guard let cwd = session.cwd else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
