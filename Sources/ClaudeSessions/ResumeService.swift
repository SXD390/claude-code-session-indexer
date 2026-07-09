import AppKit
import Foundation

/// POSIX shell quoting for embedding UNTRUSTED strings (cwd paths, ids) into a generated
/// shell command. Wrapping a value in single quotes makes every byte between the quotes
/// literal to the shell — `$(...)`, backticks, `;`, `&`, `|`, `>`, newlines, and double quotes
/// are ALL inert inside single quotes. The only character that can end a single-quoted run is a
/// single quote itself, which we close/escape/reopen as `'\''`. This is the one correct way to
/// interpolate attacker-influenced text into a script; never use double quotes (they still expand
/// `$`, backticks, and `\`).
enum Shell {
    static func singleQuote(_ s: String) -> String {
        // Invariant: the returned string is exactly one shell word equal to `s` verbatim.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Clipboard + one-click "resume in Terminal" actions.
enum ResumeService {

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Opens the session in the user's default terminal by writing an executable
    /// .command file and opening it — no Automation permission prompt needed.
    ///
    /// SECURITY (this is the sharpest edge in the app — it writes a shell script from
    /// transcript-derived data and executes it):
    ///  - The session id is re-validated as a canonical UUID here, at the point of use, so it
    ///    can never carry shell metacharacters or extra CLI flags even if a poisoned cache or a
    ///    crafted session descriptor bypassed the scanner's UUID filename filter. If it is not a
    ///    UUID we refuse to generate the script.
    ///  - The cwd (untrusted: it comes straight from the transcript) is single-quoted via
    ///    `Shell.singleQuote`, so a cwd like `/tmp/x";calc;#` or one containing `$()`, backticks,
    ///    `;`, or newlines is inert. `cd … || exit 1` also aborts before `claude` runs if the
    ///    directory is gone, so a bogus cwd can never cause execution in the wrong place.
    ///  - The filename is derived from the (sanitized) title with all path separators and dots
    ///    stripped, so the title can neither traverse (`../`) nor create a dotfile/reserved name.
    static func resumeInTerminal(session: SessionMeta) {
        guard let script = makeResumeScript(session: session) else {
            NSSound.beep()   // refused: invalid (non-UUID) session id.
            return
        }

        let dir = SessionStore.appSupportDir.appendingPathComponent("resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent(safeCommandFileName(for: session))

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            // 0o700: owner-only rwx. The script only needs to be executable by the user who
            // launches it; there is no reason for group/other to read or run it.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
        } catch {
            NSSound.beep()
        }
    }

    /// Pure (side-effect-free) builder for the resume script body. Returns nil when the session
    /// id is not a canonical UUID, in which case NO script is produced. Kept separate from the
    /// file write/open so the exact bytes we would execute can be inspected by tests.
    static func makeResumeScript(session: SessionMeta) -> String? {
        // Invariant: only ever build a resume script for a canonical-UUID session id.
        guard SessionMeta.isValidSessionId(session.sessionId) else { return nil }

        var script = "#!/bin/zsh\n"
        if let cwd = session.cwd, !cwd.isEmpty {
            // Single-quoted → literal; `|| exit 1` → never run `claude` in the wrong directory.
            script += "cd \(Shell.singleQuote(cwd)) || exit 1\n"
        }
        // sessionId is a validated UUID (guard above); single-quote it anyway as defense in depth
        // so it is a single, flag-free argument to `claude`.
        script += "exec claude --resume \(Shell.singleQuote(session.sessionId))\n"
        return script
    }

    /// Builds a filesystem-safe `.command` filename from the session title. Everything outside
    /// `[A-Za-z0-9 _-]` is dropped (so no `/`, no `.`, hence no path traversal and no dotfiles),
    /// the result is trimmed and length-capped, and it falls back to the UUID prefix when empty.
    private static func safeCommandFileName(for session: SessionMeta) -> String {
        let sanitized = session.displayTitle
            .replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            // Strip leading/trailing dots, dashes, and spaces so the name can't start with `.`
            // (dotfile) or `-` (option-like) and can't be a lone `.`/`..`.
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
            .prefix(40)
        let base = sanitized.isEmpty ? String(session.sessionId.prefix(8)) : String(sanitized)
        return base + ".command"
    }

    static func revealTranscript(session: SessionMeta) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.transcriptPath)])
    }

    static func openProjectInFinder(session: SessionMeta) {
        guard let cwd = session.cwd, !cwd.isEmpty else { return }
        let url = URL(fileURLWithPath: cwd)
        // SECURITY: cwd is untrusted. `NSWorkspace.open` on a bundle/app would LAUNCH it, so only
        // `open` (browse) a plain, non-package directory; anything else is merely revealed in
        // Finder, which never executes it.
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
