# Security Audit — Claude Code Session Indexer (Web component)

- **Date:** 2026-07-10
- **Reviewer:** Adversarial security review (Claude Code)
- **Component:** `web/` — zero-dependency Node HTTP server + single-page app
- **Result:** No open Critical/High issues. 1 High + 1 Medium + 2 Low fixed; the rest verified-safe or accepted for a single-user local tool.

> This report consolidates and supersedes an earlier same-day draft of `web-audit.md`. Its findings F1/F2 are preserved here as **W-01/W-02**; this version additionally documents three fixes made in a later pass (W-03, W-05, W-06), a fuller verification battery, and two more accepted risks (W-12, W-13).

## Scope

In scope (only):

- `web/server.js` — the HTTP server (stdlib only), bound to `127.0.0.1:4747`.
- `web/public/index.html`, `web/public/app.js`, `web/public/style.css` — the SPA.

Explicitly **out of scope / not touched:** `Sources/`, `scripts/`, `Package.swift`, `README.md`, `LICENSE`, and all git operations.

## What the component does (attack surface)

A local developer tool that:

1. Reads Claude Code transcripts from `~/.claude` (overridable via `CSI_CLAUDE_DIR`) and serves an SPA.
2. Lists / previews / searches sessions and returns usage analytics.
3. Generates AI summaries / pickup briefs / handoffs by **spawning the `claude` CLI** (`claude -p …`).
4. **Opens a terminal** to resume a session (writes a `.command`/shell script and launches it).
5. **Writes `PROGRESS.md` / `CLAUDE.md`** into a session's project directory.

It is local-only, but it opens a network port, shells out, and writes files — so it is treated as a real attack surface. The dominant threat is a **malicious web page in the user's browser** driving the loopback server (CSRF / DNS-rebinding), because that turns "local only" into "remotely triggerable side effects."

## Methodology

- Manual code review of every request-handling path, every process spawn, every filesystem read/write, and every DOM sink.
- Traced each request parameter (session id, `q`, `from`/`to`, request body, `Host`/`Origin` headers) from ingress to sink.
- Built an **isolated fixture** (temporary `HOME` + `CSI_CLAUDE_DIR`, a synthetic transcript whose `cwd` points at a throwaway `/tmp`-style directory, and a pre-seeded `handoffs.json`) so the write path could be exercised **without invoking the real `claude` CLI, without touching real `~/.claude`, and without writing into any real project**. Resume was **not** invoked (it would spawn a real terminal).
- Ran the server against the fixture and drove the endpoints with `curl`, asserting both allow and deny behavior. Server logs were checked for errors; the server was stopped after testing.

## Threat model audited

1. Path traversal / arbitrary file read.
2. Arbitrary file write.
3. Command injection (resume + summary/brief/handoff spawns).
4. Network exposure / SSRF / DNS-rebinding / CSRF.
5. XSS in the SPA (attacker-influenceable transcript content).
6. Resource / DoS.
7. Information disclosure.

## Findings summary

| ID | Severity | Component | Description | Status |
|----|----------|-----------|-------------|--------|
| W-01 | **High** | server.js / app.js | No `Host`/`Origin`/CSRF checks — a malicious site (or DNS-rebound page) could drive file writes, terminal spawns, and `claude` runs on the loopback server | **Fixed** |
| W-02 | Low | server.js `serveStatic` | Static-file guard used `startsWith(PUBLIC_DIR)`, which also accepts sibling dirs like `public-secret` | **Fixed** |
| W-03 | Medium | server.js request router | Session id not validated as a UUID — enabled a per-request full-directory re-scan (request amplification) and left the resume-argv safety on an implicit invariant | **Fixed** |
| W-04 | Low | server.js `resumeInTerminal` | Command-injection surface in resume script/spawn | **Mitigated** (no injection; hardened by W-03) |
| W-05 | Low | server.js `deepSearch` | Unbounded per-line processing of transcript lines | **Fixed** |
| W-06 | Info | server.js responses | Missing hardening headers (nosniff / frame-deny / CSP) | **Fixed** |
| W-07 | Info | server.js `parseTranscript` / `extractPreview` | Whole-file reads of very large transcripts | **Accepted** |
| W-08 | Info | server.js `writeHandoff` | Write target derived from transcript-recorded `cwd`; follows symlinks | **Accepted** (client cannot influence path — verified) |
| W-09 | Info | server.js API errors | Error messages echo the user's own absolute paths | **Accepted** |
| W-10 | Info | app.js DOM rendering | XSS review of every `innerHTML` sink | **Verified — no issue** |
| W-11 | Info | server.js `server.listen` | Bind address | **Verified — loopback only** |
| W-12 | Info | server.js CLI endpoints | No rate limiting on spend-incurring `claude` runs | **Accepted** |
| W-13 | Info | handoff generation | LLM prompt-injection can steer generated `PROGRESS.md`/`CLAUDE.md` | **Accepted** |

---

## Detailed findings

### W-01 — CSRF / DNS-rebinding on the loopback API — **High — Fixed**

**Where:** `server.js` request handler top (`hostHeaderOk` L1494, `originHeaderOk` L1499, gate L1509, custom-header gate L1524); client wrapper `app.js` `apiFetch` L218.

**Risk.** The server originally ignored `Host` entirely ("host is irrelevant for routing") and required no CSRF token. Any website the user visited could:

- POST `…/resume` → **spawn a terminal** on the user's machine.
- POST `…/summary` / `…/brief` / `…/handoff` → **run the `claude` CLI** (tokens/cost, side effects).
- POST `…/handoff/write` → **write files** into a project directory.
- Via **DNS rebinding** (a hostname re-pointed at `127.0.0.1`), also **read** `/api/sessions` (titles, prompts, cwd paths) despite the absence of CORS headers.

For a localhost tool this is the highest-value class: it converts "local only" into remotely triggerable side effects.

**Remediation (defense in depth, zero-dependency):**

1. **Host allowlist on every request** — `Host` must be a loopback literal (`127.0.0.1` / `localhost` / `[::1]` / `::1`, optional port). A DNS-rebound page still sends `Host: attacker.example` and is rejected with `403`. This defeats rebinding for *all* routes, including static assets, so a rebound page cannot even load the app.
2. **Origin allowlist** — when `Origin` is present it must be a loopback origin; cross-origin `fetch`/form POSTs are rejected.
3. **Mandatory custom header** — every `/api/*` request must carry `X-CSI-Request: 1`. A cross-origin page cannot add a custom header without triggering a CORS preflight that the server never approves, and a "simple" (no-preflight) request cannot include it at all. The SPA sends it through a single `apiFetch()` wrapper that all 10 call sites use.
4. **No CORS headers are ever emitted**, so responses remain unreadable cross-origin regardless.

**Verification:**

- Good request (loopback `Host`, `X-CSI-Request: 1`) → `200`.
- Missing `X-CSI-Request` → `403 {"code":"CSRF"}`.
- `Host: evil.com` → `403 Forbidden`.
- `Origin: http://evil.com` → `403 Forbidden`.
- `POST …/handoff/write` cross-origin and with a bad `Host` → `403`, and the target files were **not** modified.

### W-02 — Static-file prefix-match traversal — **Low — Fixed**

**Where:** `server.js` `serveStatic` L1455.

**Risk.** `path.join(PUBLIC_DIR, rel)` followed by `filePath.startsWith(PUBLIC_DIR)` accepts sibling directories whose names merely *begin with* the public dir's path (e.g. a hypothetical `…/public-secret/…`), because `startsWith` is a substring test, not a path-boundary test. Ordinary `../` escapes were already blocked and no such sibling exists today (so it was not exploitable to reach `server.js`), but the check was incorrect.

**Remediation.** Require the resolved path to be `PUBLIC_DIR` itself or to start with `PUBLIC_DIR + path.sep`.

**Verification.** `GET /%2e%2e/server.js` and `--path-as-is /../server.js` → `404 Not found` (no source disclosure).

### W-03 — Session id not validated as a UUID — **Medium — Fixed**

**Where:** `server.js` router gate L1531–1535; ids consumed by `getSessionMeta` (L786) and `resumeInTerminal` (L1352).

**Risk.** Session-scoped routes captured the id with `([^/]+)` and passed it on unvalidated. It was **safe from path traversal by construction** (the id is never joined into a path; it is only compared for equality against UUID-named transcript stems, and `getSessionMeta` returns `null` for anything unknown). However:

- A bogus id makes `getSessionMeta` fall through to a **full `listTranscripts()` re-scan (readdir of every project dir) on every request** — cheap request amplification / DoS.
- The resume path interpolates the id into a generated shell script and a Windows `cmd` string; its safety depended on the *implicit* invariant that ids are always UUIDs. That invariant should be explicit and enforced at the boundary.

**Remediation.** A single gate rejects any session-scoped route whose id is not a UUID:

```js
const sessionScoped = pathname.match(/^\/api\/sessions\/([^/]+)(?:\/|$)/);
if (sessionScoped && !UUID_RE.test(sessionScoped[1])) {
  return sendJson(res, 400, { error: 'Invalid session id', code: 'BAD_ID' });
}
```

This makes the id **provably** free of shell metacharacters and path separators before it can reach any spawn or scan.

**Verification.** `GET /api/sessions/not-a-uuid/preview` → `400 {"code":"BAD_ID"}`; a valid UUID → `200`.

### W-04 — Command-injection surface in resume/spawn — **Low — Mitigated (no injection found)**

**Where:** `server.js` `runClaude` spawn (L902), `resumeInTerminal` (L1352), macOS `.command` generation (L1358–1363), Linux `inner` (L1390).

**Assessment.** No shell-string interpolation of untrusted data reaches a shell:

- All process launches use **argv arrays** (`spawn(claude, ['-p', instruction, '--model', 'haiku'])`, `spawn('open', [scriptPath])`, `spawn(bin, ['-e','sh','-c', inner])`). There is no `sh -c` built from string concatenation of request data, and no `shell: true`.
- The excerpt handed to `claude` is passed on **stdin**, never as an argument.
- In the generated resume script, `cwd` is single-quoted via `shellQuoteSingle` (escapes embedded quotes) on macOS/Linux; the session id is interpolated but, per **W-03**, is now a validated UUID (hex + dashes only) — no metacharacters possible.
- The `.command` filename is derived from the session title through `sanitizeFileName`, which strips to `[A-Za-z0-9 _-]` and caps length — no traversal or metacharacters.

**Residual (accepted).** On **Windows**, `resumeInTerminal` wraps `cwd` in double quotes for `start /D "<cwd>"` with `windowsVerbatimArguments`. A `cwd` containing a double quote would be fragile there (Windows paths cannot legally contain `"`). `cwd` originates from a Claude Code transcript (a locally trusted file); this is an accepted residual for the Windows path and is not reachable remotely (W-01). Resume was not executed during testing per the audit constraints.

### W-05 — Unbounded per-line work in deep search — **Low — Fixed**

**Where:** `server.js` `deepSearch` L1293.

**Risk.** Deep search streams transcripts line-by-line (good), but a single pathological multi-megabyte JSONL line would be `toLowerCase()`'d and `JSON.parse`'d in full, spiking CPU/RAM.

**Remediation.** Skip any line longer than 1,000,000 chars (real transcript lines are far smaller):

```js
if (line.length > 1000000) return; // DoS guard
```

**Verification.** Deep search over the fixture returned correct results (`q=login` → 2 hits) with the guard in place.

### W-06 — Missing hardening response headers — **Info — Fixed**

**Where:** `server.js` `SECURITY_HEADERS` L1424, applied in `sendJson` (L1436) and `serveStatic` (L1467); CSP for HTML L1472.

**Remediation.** Every response now carries `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, and `Referrer-Policy: no-referrer`. The SPA document additionally gets a Content-Security-Policy:

```
default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';
img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none';
form-action 'none'; frame-ancestors 'none'
```

`script-src 'self'` (no inline scripts — the SPA has none) is defense-in-depth for the XSS class; `frame-ancestors 'none'` blocks clickjacking / rebind-in-iframe. `'unsafe-inline'` is required only for **styles** (the app sets `style="…"` attributes) and `data:` only for the inline SVG favicon.

**Verification.** `GET /` returns all four headers; `HEAD /app.js` returns nosniff. The CSP does not restrict `<a download>` blob downloads (the Journal export), which are not governed by fetch/navigation directives.

### W-07 — Whole-file reads of large transcripts — **Info — Accepted**

**Where:** `server.js` `parseTranscript` (L337) and `extractPreview` (L567) call `fsp.readFile(filePath, 'utf8')` (entire file into memory).

**Assessment.** A 47MB+ transcript is fully loaded per parse/preview request. This is inherent to matching the native app's analytics accuracy (counts/usage require the full file) and to building briefs/handoffs from the conversation tail. Request **bodies** are already capped at 1MB (`readBody`, L1443). For a single-user local tool reading the user's own files — and with remote abuse now blocked by W-01 — this is an accepted risk rather than a remotely exploitable amplifier. Deep search (the one endpoint that scans *all* files) streams line-by-line and is now line-length-guarded (W-05).

### W-08 — Handoff write target = transcript `cwd` (symlink-following) — **Info — Accepted**

**Where:** `server.js` `writeHandoff` (L1214), `insertProgressSection` (L1184), `upsertClaudeBlock` (L1200).

**Assessment.** The write endpoint is designed to write into the session's project directory. Two properties were verified as safe:

- **The client cannot influence the target path.** The destination is `path.join(meta.cwd, 'PROGRESS.md' | 'CLAUDE.md')`, where `meta.cwd` is re-derived server-side from the transcript and the filenames are fixed constants. The request body contributes only the boolean `includeClaudeMd`. A test POST carrying rogue `cwd`, `path`, and `filename` body fields wrote **only** into the intended directory; `/tmp/evil` and any `/etc/...` traversal did not occur.
- **Existing content is preserved.** `PROGRESS.md` gets a new dated section inserted after the title (old entries retained); `CLAUDE.md` gets an idempotent fenced block appended (existing notes retained). Verified on-disk.

**Residual (accepted).** `meta.cwd` comes from the transcript. An attacker who can already write a transcript under `~/.claude` with a crafted `cwd` (or plant a symlink at `PROGRESS.md`) could cause a write elsewhere **if** the user then generates and writes a handoff for that session. This requires pre-existing local filesystem write access to `~/.claude` (an attacker with that access can already do worse directly), the target files are fixed and content-preserving, and the whole flow is CSRF-protected (W-01). Accepted for a single-user local tool.

### W-09 — Error messages echo absolute paths — **Info — Accepted**

**Where:** e.g. `writeHandoff` `CWD_MISSING` messages (L1223, L1229), and the `e.message` returned by the brief/handoff/summary/resume handlers.

**Assessment.** These paths are the user's own and aid usability; uncaught errors return a generic `500` with no stack trace (router `catch`). Not reachable cross-origin after W-01. Accepted.

### W-10 — XSS in the SPA — **Info — Verified, no issue**

**Where:** all `innerHTML` sinks in `app.js`; `esc` (L66), `highlight` (L1442), chart tooltip (L999–1001).

**Assessment.** Every place attacker-influenceable transcript content (titles, prompts, assistant text, search snippets, cwd/file paths, model names) reaches the DOM, it passes through `esc()` (escapes `& < > " '`). Specifically checked:

- Session rows, detail pane, overview, journal, brief/handoff/usage cards, deep-search groups — all interpolate via `esc()`.
- **Search snippet highlighting** (`highlight`), the prime suspect: builds output as `esc(fragment) + '<mark>' + esc(match) + '</mark>'` — only escaped fragments surround literal `<mark>` tags. No unescaped untrusted text is emitted.
- Chart tooltips write untrusted labels via **`textContent`**, not `innerHTML`.
- Colors/positions come from constant palettes (`projColor`, `tierColor`) and numeric computations, not from untrusted strings.

No fix required. The added CSP (W-06) is defense-in-depth for this class.

### W-11 — Network bind — **Info — Verified**

**Where:** `server.js` `server.listen(PORT, HOST, …)` (L1703) with `HOST = '127.0.0.1'`.

**Assessment / Verification.** Bind is strictly loopback. `lsof` confirmed `TCP 127.0.0.1:4788 (LISTEN)` (IPv4 loopback), not `0.0.0.0`. Combined with the Host allowlist (W-01), the server is not reachable from the LAN and not rebinding-reachable from the browser.

### W-12 — No rate limiting on spend-incurring endpoints — **Info — Accepted**

**Where:** `…/summary`, `…/brief`, `…/handoff` handlers (each calls `runClaude`, which spawns `claude -p`).

**Assessment.** These endpoints incur Claude API spend and have no rate limit or concurrency cap beyond the per-run 3-minute timeout. Accepted: only the same-origin SPA can reach them (W-01), each run is triggered by an explicit user action in the UI, and there is a single local user. Worth revisiting if the tool ever gains multi-user or authenticated remote access.

### W-13 — Prompt-injection into generated handoff files — **Info — Accepted**

**Where:** `generateHandoff` → `writeHandoff` (`PROGRESS.md` / `CLAUDE.md`).

**Assessment.** A malicious transcript could steer the `claude`-generated handoff text that is then written to `PROGRESS.md`/`CLAUDE.md`. This is inherent LLM risk: the output is confined to those two fixed files inside the session's own `cwd`, writing requires an explicit user click, and the content is markdown (not executed). Accepted; users should review generated handoffs before acting on them (as they would any AI output).

---

## Verification results (against an isolated fixture)

Server started with `HOME=<temp>` and `CSI_CLAUDE_DIR=<fixture>` on port 4788; a synthetic transcript with `cwd=<scratch>/handoff-target`; `handoffs.json` pre-seeded so the write path runs without spawning `claude`. Resume was **not** invoked; no real project was written.

| # | Test | Expected | Result |
|---|------|----------|--------|
| 1 | `GET /api/sessions` (good header/Host) | 200 + 1 session | PASS — 200, session parsed (title, cwd) |
| 2 | `GET /api/sessions` (no `X-CSI-Request`) | 403 CSRF | PASS — 403 `{"code":"CSRF"}` |
| 3 | `GET /api/sessions` `Host: evil.com` | 403 | PASS — 403 Forbidden |
| 4 | `GET /api/sessions` `Origin: http://evil.com` | 403 | PASS — 403 Forbidden |
| 5 | `GET /` static | 200 + CSP/nosniff/frame/referrer | PASS — all headers present |
| 6 | `GET …/not-a-uuid/preview` | 400 BAD_ID | PASS — 400 `{"code":"BAD_ID"}` |
| 7 | `GET /api/search?q=login` | results | PASS — 200, 2 hits |
| 8 | `GET …/<uuid>/preview` | messages | PASS — 200, user+assistant |
| 9 | `POST …/handoff/write` cross-origin | 403, no write | PASS — 403, files untouched |
| 10 | `POST …/handoff/write` bad `Host` | 403, no write | PASS — 403, files untouched |
| 11 | `POST …/handoff/write` same-origin + rogue body path fields | 200, writes only into target | PASS — 200, only target written |
| 12 | Rogue `/tmp/evil` / `/etc` paths | absent | PASS — absent (body fields ignored) |
| 13 | `PROGRESS.md` / `CLAUDE.md` after write | old content preserved, new added | PASS — old entries retained; new section + fenced block added |
| 14 | Static traversal `/../server.js` | 404 | PASS — 404 |
| 15 | `GET /api/usage` | 200 totals | PASS — 200, cost/daily/byModel present |
| 16 | `HEAD /app.js` | 200 + nosniff | PASS — 200 |

Server log showed **no request errors / stack traces**. Server stopped after testing.

## Residual risk / assumptions

- **Single-user, local tool.** The server trusts the local machine's user; it offers no authentication and does not need it once cross-origin/rebind access is closed (W-01). Anyone with a shell as this user already has full access.
- **Trusts local filesystem contents.** Transcripts under `~/.claude` (and their `cwd` fields, titles, message text) are treated as data the user themselves produced. An attacker who can already write files there has local write access and can cause more direct harm than steering a handoff write (W-08) or a generated file (W-13). Session titles/text are rendered safely (W-10) and used only in argv arrays / stdin, never a shell (W-04).
- **Windows resume quoting (W-04)** is the weakest spawn path and relies on `cwd` from a trusted transcript; not remotely reachable. Consider migrating the Windows path off the `cmd /c start "" /D "<cwd>"` string toward a `.cmd` file written with quoting parity to the macOS `.command` approach if Windows becomes a supported target.
- **Large-transcript CPU/RAM (W-07)** and **CLI spend (W-12)** are accepted; the practical mitigations (1MB body cap, streamed+guarded deep search, same-origin-only reachability, explicit user actions) bound the realistic exposure for a single user.
- **`X-CSI-Request` header requirement** assumes a modern browser that enforces CORS preflight for custom headers — true for all current browsers. The `Host`/`Origin` allowlist is the primary rebinding defense and does not depend on that assumption.

---

## Verification & provenance

All fixes described above are present in the shipped `web/server.js` on `main`. The W-01/W-02
defenses landed in commit `92ad2ee`; the W-03 (UUID route gate), W-05 (deep-search line cap), and
W-06 (hardening headers + CSP) fixes were verified live and committed in `185df77`. Line numbers
in this report reference the code as of that commit. The CSRF/Host/Origin behavior and the header
set are re-verified on every push by the security self-test wired into CI (`.github/workflows/build.yml`).
