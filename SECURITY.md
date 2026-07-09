# Security Policy

Claude Code Session Indexer is a **local-only, single-user developer tool**. It reads your
Claude Code transcripts from `~/.claude`, and — only when you explicitly ask — spawns the
`claude` CLI, opens your terminal to resume a session, or writes `PROGRESS.md` / `CLAUDE.md`
into a project directory. It makes **no external network requests**, has **no dependencies**,
and the web dashboard binds strictly to `127.0.0.1`.

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for anything
exploitable.

- Use GitHub's **[Private vulnerability reporting](https://github.com/SXD390/claude-code-session-indexer/security/advisories/new)**
  (Security tab → Report a vulnerability), or
- Open a regular issue **only** for non-sensitive, low-risk hardening suggestions.

Please include: affected component (macOS app or web server), version/commit, a description,
and reproduction steps. We aim to acknowledge within a few days. As a solo open-source
project there is no formal SLA or bug-bounty, but credible reports will be addressed and
credited (if you wish) in the fix.

## Scope & threat model

**In scope**

- Path traversal / arbitrary file read or write beyond the intended directories
- Command or argument injection via the process-spawning code paths (resume, summaries,
  briefs, handoffs)
- Cross-site request forgery / DNS-rebinding against the localhost web server (a malicious
  website triggering file writes or process spawns)
- Cross-site scripting in the web SPA from transcript content

**Out of scope / accepted risks** (documented in [`docs/security/`](docs/security/))

- The tool **trusts the contents of your local `~/.claude` directory**. An attacker who can
  already write arbitrary files into your home directory has higher privileges than this tool
  grants; we defend against transcript content being turned into code execution, but not
  against a fully compromised local account.
- It is a **single-user local tool** with no authentication between you and your own machine.
- Downloadable builds are **ad-hoc signed, not notarized** — see below.

## Audits

Full security audit reports live in [`docs/security/`](docs/security/):

- [`web-audit.md`](docs/security/web-audit.md) — the Node web server + SPA
- [`macos-audit.md`](docs/security/macos-audit.md) — the native macOS app

Automated scanning runs in CI on every push (CodeQL for JavaScript, OpenSSF Scorecard, and
secret scanning).

## Supply chain

- **Zero runtime dependencies** on both platforms (no npm packages, no Swift packages beyond
  the standard library). There is no dependency tree to compromise and `npm audit` is
  trivially clean.
- Everything is built from source in this repository.

## Code signing & distribution

The recommended way to install is **building from source** (`./scripts/build_app.sh`) — that
binary is locally compiled and carries no Gatekeeper quarantine.

An optional ad-hoc `.dmg` (`./scripts/make_dmg.sh`) is provided for convenience, but because it
is **not notarized by Apple**, macOS Gatekeeper will warn that it is from an "unidentified
developer" on first launch. See [`docs/security/macos-audit.md`](docs/security/macos-audit.md)
for the trade-offs and the path to Developer ID signing + notarization.
