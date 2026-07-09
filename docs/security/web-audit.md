# Security Audit — Web Component

**Component:** `web/server.js`, `web/public/{index.html,app.js,style.css}`
**Type:** Adversarial source review with live verification
**Date:** 2026-07-09
**Result:** 1 Critical + 1 Low/Medium finding, both **fixed** and verified. No open Critical/High issues.

## Scope & methodology

The web component is a zero-dependency Node HTTP server bound to `127.0.0.1:4747` that serves a
single-page app and an `/api/*` surface over the user's local Claude Code transcripts. It reads
files under `~/.claude` (or `CSI_CLAUDE_DIR`), spawns the `claude` CLI for AI summaries / briefs /
handoffs, opens a terminal to resume a session, and writes `PROGRESS.md` / `CLAUDE.md` into a
session's project directory.

Because it opens a network port, shells out, and writes files, it was reviewed as a real attack
surface. Every request value that flows into a filesystem path, a spawned process, or the DOM was
traced. Findings were confirmed with a running instance and, where useful, a unit test.

## Threat model

- **Untrusted input:** transcript contents (titles, prompts, assistant text, `cwd`) — anything
  that can land as a `.jsonl` under `~/.claude`. Also: any website open in the user's browser,
  which can send requests to `127.0.0.1`.
- **Trusted:** the local user account and the integrity of the user's own home directory.
- **Assets at risk:** private transcript contents; the user's shell/terminal (process spawns);
  the user's project directories (file writes); Claude API spend (CLI calls).

## Findings

| ID | Severity | Component | Summary | Status |
|----|----------|-----------|---------|--------|
| F1 | **Critical** | server.js request handling | No origin validation → CSRF + DNS-rebinding against every endpoint | **Fixed** |
| F2 | Low/Medium | server.js `serveStatic` | Prefix-match path check allowed sibling-directory escape | **Fixed** |
| N1 | Info | server.js Windows resume | Verbatim cwd quoting (defense-in-depth only) | Accepted |
| N2 | Info | handoff generation | LLM prompt-injection into generated files | Accepted |
| N3 | Info | CLI endpoints | No rate limiting on spend-incurring endpoints | Accepted |
| N4 | Info | error responses | Filesystem paths echoed in errors | Accepted |

### F1 — CSRF + DNS rebinding on the localhost dashboard (Critical) — FIXED

The server performed **no request-origin validation**. It routed on `new URL(req.url, 'http://127.0.0.1')`
with a fixed base, never inspected the `Host` header, required no `Origin` check, and required no
custom header. Consequences:

- **CSRF:** any website open in the user's browser could fire "simple" no-cors POSTs at
  state-changing endpoints — `POST /api/sessions/:id/resume` (spawns a terminal),
  `/handoff` + `/handoff/write` (writes files into a project dir), `/summary` `/brief` `/handoff`
  (incur Claude API spend). The side effects fire even though the attacker can't read the opaque
  response.
- **DNS rebinding:** an attacker rebinds `evil.com` → `127.0.0.1`; the page becomes "same-origin"
  with the server and can read full private transcripts from the GET endpoints
  (`/api/sessions`, `/api/search`, `/api/sessions/:id/preview`, `/usage`).

**Remediation (three layers, no CORS headers introduced):**

1. `hostHeaderOk()` — rejects any request whose `Host` is not a loopback literal
   (`127.0.0.1` / `localhost` / `[::1]`, optional port) with **403**. Applied to *every* request
   including static assets, so a DNS-rebound page (which still sends `Host: evil.com`) cannot even
   load the app. This is the primary DNS-rebinding defense.
2. `originHeaderOk()` — if an `Origin` header is present and is not a loopback origin → **403**.
   Blocks cross-origin fetch/form POSTs.
3. Custom-header gate — every `/api/*` request must carry `X-CSI-Request: 1`; missing → **403**.
   A cross-origin page cannot attach this without a CORS preflight the server never approves, and
   a "simple" request cannot include a custom header at all.

Client side, `app.js` gained an `apiFetch()` wrapper that attaches the header, and all `/api/*`
calls were routed through it.

**Verification (live):** legit call → 200; CSRF POST without the header → 403; attacker `Host` → 403;
cross-origin `Origin` → 403; same-origin `Origin` → 200; static asset with attacker `Host` → 403.
Confirmed no `Access-Control-Allow-*` headers exist anywhere.

### F2 — Path traversal via prefix match in static serving (Low/Medium) — FIXED

`serveStatic()` guarded with `!filePath.startsWith(PUBLIC_DIR)` (no trailing separator). A resolved
path such as `.../web/public-secret/keys.txt` passes that check because the string starts with
`.../web/public`. Ordinary `../` escapes were already blocked, but the sibling-directory case was
not. Changed to `filePath === PUBLIC_DIR || filePath.startsWith(PUBLIC_DIR + path.sep)`. Unit-tested:
the old check served the sibling-dir file; the new check blocks it while still serving legitimate
assets.

## Reviewed — no fix required (working as designed)

- **Command execution** (`resumeInTerminal`, `runClaude`): `sessionId` is always a validated UUID
  (the scanner only admits UUID-named transcript stems); `cwd` is passed through correct POSIX
  single-quote escaping; the `claude` CLI is spawned with an **argv array** (no `shell: true`) with
  the excerpt piped over **stdin**. No shell-string interpolation of untrusted data — no injection
  reachable.
- **Handoff file writes:** the target directory (`meta.cwd`) and the two filenames are entirely
  server-derived; the client sends only an `includeClaudeMd` boolean. No client-controlled path.
- **Frontend XSS:** untrusted transcript text is consistently escaped via an `esc()` helper (including
  in attributes) and `textContent` (chart tooltips); the deep-search highlighter escapes fragments
  before wrapping matches.
- **Request body size:** capped at ~1 MB; the socket is destroyed past the limit.

## Accepted / residual risk

- **N1 – Windows resume quoting:** `cwd` comes from the user's own transcript (Windows paths cannot
  contain `"`), and the endpoint is behind the F1 defenses; left as-is (no Windows environment to
  validate a change). Defense-in-depth only.
- **N2 – Prompt injection into generated files:** a malicious transcript could steer the
  `claude`-generated handoff, which is then written to `PROGRESS.md`/`CLAUDE.md`. This is inherent
  LLM risk; output is confined to those two files inside the session's own `cwd`, and writing
  requires an explicit user click.
- **N3 – No rate limiting** on the spend-incurring CLI endpoints. Acceptable now that only the
  same-origin app can reach them.
- **N4 – Error messages** may echo filesystem paths. Localhost, self-owned data; low value.
- **Trust boundary:** the tool trusts the contents of the local `~/.claude` directory and is a
  single-user local application with no authentication between the user and their own machine.
