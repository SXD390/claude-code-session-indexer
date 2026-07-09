# Security Audit — macOS (Swift) Component

**Component:** "Claude Code Session Indexer" — native SwiftUI macOS app (SPM target `ClaudeSessions`)
**Audit date:** 2026-07-10
**Auditor:** Adversarial security review (macOS/Swift scope only)
**Scope:** `Sources/ClaudeSessions/**.swift`, `scripts/build_app.sh`
**Out of scope (handled separately):** `web/`, `README.md`, `LICENSE`. No git operations performed.

---

## 1. What the app is

A single-user developer tool that indexes Claude Code transcripts under `~/.claude` (overridable
via `CSI_CLAUDE_DIR`). Beyond read-only browsing it performs three privileged actions:

1. **Resume-in-Terminal** — writes an executable `.command` shell script (`cd <cwd>` +
   `claude --resume <id>`), `chmod`s it, and `open`s it (`ResumeService.swift`).
2. **AI summary / brief / handoff** — spawns the `claude` CLI as a child process via Foundation
   `Process` (`SummaryService.swift`, `BriefService.swift`, `HandoffService.swift`).
3. **Handoff writes** — writes `PROGRESS.md` / `CLAUDE.md` into a session's project directory
   (`HandoffService.swift`).

## 2. Methodology

Manual code review with data-flow tracing from every untrusted source to every sink, followed by
adversarial dynamic testing. I treated as **untrusted** all data derived from transcript content
and filesystem layout under `~/.claude`: `sessionId`, `cwd`, `gitBranch`, `model`, titles
(`customTitle` / `aiTitle` / `firstPrompt` / `displayTitle`), transcript message text, and the
model output produced by `claude -p` (it is influenced by that text). The premise is that anyone or
anything can drop a `.jsonl` (or a `sessions/*.json` descriptor) under `~/.claude`, and a cloned
repo's transcript can carry an adversarial `cwd` or title.

Sinks audited: `Process` spawns (shell vs. argv), the generated `.command` script, project-dir file
writes, and Finder/`open` calls. Verification was done with a headless, env-gated self-test harness
(`--security-selftest`, gated on `CSI_SECURITY_SELFTEST=1`) that drives the real code against a
malicious fixture, plus an independent `zsh -n` / literal-execution round-trip of the generated
script.

## 3. Threat model audited

| # | Threat | Result |
|---|--------|--------|
| 1 | Command/argument injection via `Process` | No shell interpolation of untrusted data; all spawns use argv arrays. Hardened the `.command` path. |
| 2 | Injection through the generated `.command` file | **Was latent-critical** (unvalidated id, id emitted unquoted). Fixed. |
| 3 | Path traversal / clobber via handoff writes | Bounded to two fixed filenames in an existing absolute dir; marker-block hardened. |
| 4 | Symlink / crafted-filename reads outside the tree | Read-only; gated by a strict UUID filename filter. Accepted low risk. |
| 5 | Untrusted content to `claude -p` stdin | Sent via stdin/argv, never a shell. Low risk; prompt-injection into the model is mitigated downstream. |
| 6 | App hardening / distribution posture | Ad-hoc signed, no Hardened Runtime / notarization. Build script now supports Developer ID + runtime. |

## 4. Findings

| ID | Severity | Component | Description | Status |
|----|----------|-----------|-------------|--------|
| M-01 | **High** (latent) | `ResumeService.swift` | Session id was written **unquoted and unvalidated** into an executable `.command` (`exec claude --resume <id>`). Injection was prevented only by a distant UUID filename filter in `TranscriptScanner`; any poisoned cache / crafted descriptor reaching this code = arbitrary command or CLI-flag injection. | **Fixed** |
| M-02 | Medium | `Models.swift` (`resumeCommand`) | The copy-to-clipboard resume command wrapped `cwd` in **double** quotes, so a transcript `cwd` like `$(rm -rf ~)` or `x";calc;#` injects when the user pastes it. | **Fixed** |
| M-03 | Medium | `HandoffService.swift` (`writeToProject`) | Untrusted `cwd` was not required to be absolute; a relative `cwd` would resolve against the process working directory. | **Fixed** |
| M-04 | Medium | `HandoffService.swift` (`markerBlock` / `writeClaudeMd`) | Model content embedding the `CLAUDE.md` start/end marker comments could desync the marker-block replacement and orphan/garble the managed block. | **Fixed** |
| M-05 | Low | `ResumeService.swift` (`openProjectInFinder`) | `NSWorkspace.open` on a transcript-supplied `cwd` pointing at an app bundle would **launch** it instead of browsing a folder. | **Fixed** |
| M-06 | Low | `ResumeService.swift` (`.command` perms) | Script was created `0o755` (group/other readable + executable). | **Fixed** (`0o700`) |
| M-07 | Low | `scripts/build_app.sh` | Ad-hoc signature only; no Hardened Runtime, timestamp, or notarization path. | **Fixed** (opt-in Developer ID + runtime) |
| I-01 | Info | `Summary/Brief/HandoffService.swift` | `claude`-binary discovery uses `/bin/zsh -lc "command -v claude"` — a **static** command string; all `claude -p` spawns use argv arrays. No untrusted data reaches a shell. | Reviewed — no change |
| I-02 | Info | `TranscriptScanner.swift` | Reads are gated by a canonical-UUID filename filter; a symlink under `~/.claude/projects` could redirect read-only scans, but requires an attacker who already has write access to `~/.claude`. | Accepted (see §6) |

### M-01 — Unvalidated/unquoted session id in the executable `.command` (High, latent)

`Sources/ClaudeSessions/ResumeService.swift` — previously:
`script += "exec claude --resume \(session.sessionId)\n"` (unquoted), with no id validation at the
point of use.

**Risk.** The `.command` is `chmod +x`'d and `open`'d (executed by Terminal). The only thing keeping
`sessionId` benign was the UUID filename filter in `TranscriptScanner.listTranscripts`
(`UUID(uuidString: stem) != nil`), which lives in a different file and is trivially bypassed by any
future caller, a hand-edited `meta-cache.json`, or a crafted `sessions/*.json`. A `sessionId` such as
`x; rm -rf ~` yields `exec claude --resume x; rm -rf ~` (command injection); `x --dangerously-skip-permissions`
is argument injection into `claude`.

**Remediation (implemented).**
- Added a shared validator `SessionMeta.isValidSessionId(_:)` (`Models.swift:48`) — canonical UUID only.
- `ResumeService.makeResumeScript` (`ResumeService.swift:66`) now **refuses** (returns `nil`, caller
  beeps) unless the id is a valid UUID, and single-quotes the id via `Shell.singleQuote`
  (`ResumeService.swift:77`) as defense-in-depth so it is one flag-free argument.
- Extracted pure `makeResumeScript` from the write/open so the exact bytes are unit-testable without
  side effects.

### M-02 — Double-quoted cwd in the clipboard resume command (Medium)

`Sources/ClaudeSessions/Models.swift` `resumeCommand` returned `cd "\(cwd)" && …`. Double quotes still
let the shell expand `$`, backticks, and `\`. A malicious `cwd` executes the moment the user pastes.
**Fix (`Models.swift:64`):** single-quote both `cwd` and the id via the shared `Shell.singleQuote`.

### M-03 — Relative cwd in handoff writes (Medium)

`HandoffService.writeToProject` validated that `cwd` is an existing directory but not that it is
**absolute**. A relative `cwd` (`URL(fileURLWithPath:)`) would resolve against the process working
directory. **Fix (`HandoffService.swift:267`):** require `cwd.hasPrefix("/")`; still require it to be
an existing directory; writes remain limited to the hardcoded `PROGRESS.md` / `CLAUDE.md`.

### M-04 — Marker-block desync in CLAUDE.md (Medium)

`writeClaudeMd` replaces the region between the first `<!-- session-indexer:handoff:start -->` and the
first `…:end -->`. If model content (influenced by untrusted transcript text) itself contained those
markers, the next replacement could match the wrong delimiters, orphaning text or corrupting the
managed block. **Fix (`HandoffService.swift:344`):** `markerBlock` strips any embedded start/end
markers from `content` before wrapping, guaranteeing exactly one of each. User content outside the
markers was already preserved; this closes the corruption vector inside the block. (Verified: injected
markers collapse to a single start/end.)

### M-05 — openProjectInFinder could launch a bundle (Low)

**Fix (`ResumeService.swift:107`):** only `NSWorkspace.open` a plain, non-package existing directory;
otherwise `activateFileViewerSelecting` (reveal, never execute).

### M-06 — Over-permissive script mode (Low)

**Fix (`ResumeService.swift:56`):** `0o700` instead of `0o755`; the owner is the only principal that
needs to run it.

### M-07 — Signing/distribution (Low) — see §5.

## 5. Code signing & distribution

**Current state.** `scripts/build_app.sh` performs ad-hoc signing (`codesign --force -s -`): no stable
signing identity, **no Hardened Runtime**, no secure timestamp, no entitlements, not notarized. Ad-hoc
is fine for building and running on the same Mac, but on any other machine Gatekeeper will quarantine
and block it, and the binary has no tamper-evident identity.

**Change made.** The signing step is now parameterized (`scripts/build_app.sh`): it defaults to ad-hoc
for local builds, but when `CODESIGN_ID` is exported it signs with a Developer ID identity **plus
`--options runtime --timestamp`** (Hardened Runtime + secure timestamp — the prerequisites for
notarization). This is opt-in and does not change the local-dev default.

**Sandboxing.** A full App Sandbox is **impractical and not recommended** here: the app's core function
is to read `~/.claude` (outside a container), spawn the `claude` CLI, and write into arbitrary user
project directories (`session.cwd`). Under the sandbox these require broad temporary exceptions
(user-selected files, `com.apple.security.inherit`/child-process exceptions) that would negate most of
the sandbox's value while complicating the child-process model. It is honest to say this tool is a
local developer utility that intentionally operates across the user's filesystem.

**Recommendation.**
- **Local / from-source use:** keep ad-hoc — acceptable and unchanged.
- **Any distribution (even a GitHub release):** sign with **Developer ID Application** + **Hardened
  Runtime** + secure timestamp (now one env var away), then **notarize** (`xcrun notarytool submit`)
  and **staple** (`xcrun stapler staple`). Hardened Runtime is compatible with this app because it
  *spawns* `claude` as a separate executable (unaffected by library validation) rather than loading
  foreign dylibs; no special entitlements are needed. Notarization is what lets other users run it
  without the "unidentified developer" block and provides Apple's malware scan + revocation path.

## 6. Residual risk & accepted assumptions

- **Trust boundary.** The threat model assumes an attacker who can plant files under `~/.claude`. Such
  an attacker already has the user's filesystem privileges and could attack the user by many other
  means; the value of the fixes is preventing *escalation from data to code execution* through this
  app's exec/write surfaces, which is now closed.
- **Handoff target directory (I-02 / M-03).** By design, handoff writes go into the real project dir
  recorded in the transcript, which may be anywhere on disk. This is intended. It is bounded to two
  fixed filenames, requires an existing absolute directory, and `String.write(atomically:)` replaces a
  symlinked destination with a regular file (it does not follow the link to clobber the target); a
  crafted symlink could at most cause the *target's* content to be read and re-emitted into the project
  dir — low impact for a local tool. Not further constrained.
- **Prompt injection into the model.** Transcript text can steer `claude -p`'s output. That output is
  displayed, or (for handoffs) written as inert Markdown into `PROGRESS.md`/`CLAUDE.md`. It is never
  executed by this app; the marker-block hardening (M-04) prevents it from corrupting the managed
  region. Out of scope beyond that.
- **TOCTOU.** Between the directory-exists check and the write there is a small window. Given the
  local, single-user, user-initiated nature, this is accepted (noted lightly per scope).
- **Login-shell discovery.** `zsh -lc "command -v claude"` sources the user's own dotfiles. That is the
  user's environment, not attacker input; the command string is static. Accepted.

## 7. Verification

- `swift build` — clean.
- `.build/debug/ClaudeSessions --scan-test` — parses all transcripts and prints correctly; resume
  commands now render single-quoted.
- `.build/debug/ClaudeSessions --handoff-write-test <dir>` — prepend / marker-replace / content
  preservation unchanged (regression pass).
- `CSI_SECURITY_SELFTEST=1 .build/debug/ClaudeSessions --security-selftest <dir>` — **all assertions
  pass** against a malicious fixture (evil `cwd`/title with `"`, `;`, `$()`, backticks, newline,
  `rm -rf ~`; non-UUID id; injected CLAUDE.md markers): id refused when non-UUID; cwd + id single-quoted;
  no metacharacter outside quotes; handoff writes refused for missing/relative cwd and constrained to
  `PROGRESS.md`/`CLAUDE.md` inside the target; marker injection collapses to one start/end.
- Independent proof: the generated script (with an embedded single quote escaped as `'\''`) passes
  `zsh -n` and, when executed, `cd`s into the literal weird directory with **no** injection artifact
  created — confirming the quoting neutralizes the payload.

The self-test harness is permanent but **double-gated** (requires both the `--security-selftest`
argument and `CSI_SECURITY_SELFTEST=1`); it never runs in normal use, never opens a `.command`, and
never writes into a real project. It is retained as a regression guard.
