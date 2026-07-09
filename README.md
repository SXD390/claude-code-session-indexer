<div align="center">

# Claude Code Session Indexer

**Pick up any Claude Code session right where you left off.**

A beautiful, 100% local companion for the Claude Code CLI — browse every conversation,
understand where the work stands, and jump back in with one click.

Native macOS app · Web dashboard for Windows & Linux · Zero cloud, zero telemetry

[![License: MIT](https://img.shields.io/badge/License-MIT-coral.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#-macos-app)
[![Web](https://img.shields.io/badge/Web-Node%2018%2B-333?logo=javascript)](#-web-app-windows--linux--macos)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)](#)

<img src="docs/mac-detail.png" alt="Session detail with Pickup Brief" width="900">

<sub>All screenshots show generated demo data, not real sessions.</sub>

</div>

---

## Why Claude Code Session Indexer?

Claude Code stores every session as a JSONL transcript under `~/.claude/` — and then makes you
scroll a terminal picker to find them again. Plenty of tools let you *view* that history or
*count* your tokens. Claude Code Session Indexer is built around a different idea: **continuity** — getting back
into flow on work you started days ago.

|  | History viewers | Usage meters | **Claude Code Session Indexer** |
|---|:---:|:---:|:---:|
| Browse & resume sessions | ✅ | — | ✅ |
| Token & cost analytics | some | ✅ | ✅ |
| **Pickup Briefs** — AI "where you left off" + ready-to-paste next prompt | — | — | ✅ |
| **Deep search** inside every conversation, with snippets | — | — | ✅ |
| **Project Journals** — cross-session changelog per repo, exportable | — | — | ✅ |
| **Handoff files** — writes PROGRESS.md + CLAUDE.md so the next session picks up the work | — | — | ✅ |
| **Efficiency insights** — cache hit-rate coaching, cost per active hour | — | — | ✅ |
| Native macOS app (no Electron) | rare | — | ✅ |
| Time-spent tracking from transcripts | — | — | ✅ |

## The signature features

### ⏮ Pickup Briefs

Your fast lane back into flow. One click generates a brief for any session:
**State** (what was done, what was mid-flight), **Open threads** (unresolved bugs, deferred
TODOs), and a **ready-to-paste Next Prompt** that drops you back into productive work — no
re-reading a 60-message transcript to remember what you were doing.

### 🤝 Handoff files

Package a session's work for the *next* session: one click generates a dated **PROGRESS.md**
section (done / in progress / open threads / key decisions / how to verify) and a durable
**CLAUDE.md** knowledge block, previews both, and — only after you confirm — writes them into
that session's project directory. Your existing CLAUDE.md is never overwritten: the indexer
appends a clearly-marked section and replaces only its own marker block on regeneration.
A kickstart prompt ties it together so `claude` in a fresh session knows exactly where to begin.

### 🔎 Deep transcript search

Search *inside* the conversations, not just the titles. "Which session did I fix that CORS bug
in?" — highlighted snippets across hundreds of megabytes of transcripts, grouped by session.

### 📖 Project Journals

Every project gets an auto-stitched timeline of all its sessions — what happened, how long it
took, what it cost — readable like a changelog and exportable as Markdown.

### 📊 Insights

Time spent per day, tokens and estimated cost (API-equivalent) with 7/30/90-day and custom
ranges, per-model and per-project breakdowns, an hour-of-day rhythm chart — plus plain-language
efficiency insights like your prompt-cache hit rate and what it's saving you.

<div align="center">
<img src="docs/mac-insights.png" alt="Insights dashboard" width="900">
</div>

And the essentials are all there: sessions grouped by project with your custom `/rename` names
front and center, live "running now" detection, AI summaries, one-click **Resume in Terminal**,
copyable resume commands, and a conversation preview.

## 🖥 macOS app

Native SwiftUI — no Electron, no web view. Warm charcoal/cream design with light & dark mode.

```sh
git clone https://github.com/SXD390/claude-code-session-indexer.git && cd claude-code-session-indexer
./scripts/build_app.sh
open "dist/Claude Code Session Indexer.app"        # drag into /Applications to keep it
```

Requires macOS 14+ and Xcode command-line tools.

## 🌐 Web app (Windows · Linux · macOS)

The same product as a local web dashboard — one file server, **zero npm dependencies**, no build
step, bound strictly to `127.0.0.1`.

```sh
./web/start.sh                  # macOS / Linux
```

```bat
web\"Start Session Indexer.bat"         :: Windows — or just double-click it
```

Then open <http://127.0.0.1:4747>. Requires Node 18+. `/` to search, `↑↓` to navigate,
`R` to resume, `C` to copy the resume command.

<div align="center">
<img src="docs/web-overview.png" alt="Claude Code Session Indexer web dashboard" width="900">
</div>

## How it works

| Source | Used for |
|---|---|
| `~/.claude/projects/*/<uuid>.jsonl` | sessions, titles (your `/rename` names > AI titles > first prompt), messages, per-message token usage |
| `~/.claude/sessions/*.json` | live "running now" detection (PID-checked) |
| `claude -p` (your own CLI) | AI summaries & Pickup Briefs, generated on demand and cached |

- **Everything stays on your machine.** No cloud, no accounts, no telemetry, no external
  requests — the web server refuses non-localhost connections.
- **Read-only** over `~/.claude` — Claude Code Session Indexer never modifies your Claude Code data.
- **Fast**: transcripts are parsed in parallel and cached by file mtime, so token counts are
  deduplicated correctly (streaming writes duplicate usage lines — Claude Code Session Indexer accounts for that)
  and relaunches are instant.
- **Costs are estimates.** Claude Code Session Indexer prices tokens at published API rates ("API-equivalent").
  If you're on a Claude subscription, it shows what your usage *would have cost* — a measure
  of value, not a bill.

## Development

```sh
swift run ClaudeSessions                     # run the mac app from source
node web/server.js                           # run the web server
.build/debug/ClaudeSessions --scan-test      # headless: parse all transcripts, print stats
.build/debug/ClaudeSessions --usage-test     # headless: analytics engine check
.build/debug/ClaudeSessions --brief-test <id-prefix>   # headless: live Pickup Brief test
.build/debug/ClaudeSessions --handoff-test <id-prefix>  # headless: Handoff generation (no writes)
```

## License

[MIT](LICENSE) © Sudarshan Venkatesh

Claude Code Session Indexer is an independent open-source project, not affiliated with or endorsed by Anthropic.
"Claude" and "Claude Code" are trademarks of Anthropic, PBC.
