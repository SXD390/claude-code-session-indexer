# Claude Sessions

A native macOS app for browsing, searching, and resuming your Claude Code sessions.

Claude Code stores every session as a `.jsonl` transcript under `~/.claude/projects/`. This app scans those transcripts and gives you a searchable, Mac-native library of all your chats — including the names you set with `/rename`, AI-generated titles, and which sessions are running right now.

![app](docs/screenshot.png)

## Features

- **Every session, one place** — grouped by project, sorted by recency, with your prompts count and last-activity time.
- **Names front and center** — sessions you named (via `/rename`) show a tag badge; otherwise the AI title or first prompt is used.
- **Resume in one click** — "Resume in Terminal" opens your default terminal, `cd`s into the project, and runs `claude --resume <id>`. Or copy the command / session ID to the clipboard.
- **AI summaries** — generate a 2–3 sentence summary of any session on demand (uses `claude -p` with Haiku; cached on disk, flagged when stale).
- **Running-now detection** — sessions with a live `claude` process get a green dot and a sidebar filter.
- **Search** — matches names, titles, first prompts, summaries, project names, and session IDs.
- **Conversation preview** — read the user/assistant exchange without leaving the app; reveal the raw transcript in Finder.
- **Fast** — transcripts are parsed in parallel and cached (keyed by file mtime/size), so relaunches are instant.

## Build & install

Requirements: macOS 14+, Xcode command-line tools.

```sh
./scripts/build_app.sh
open "dist/Claude Sessions.app"        # or drag it into /Applications
```

For development: `swift run ClaudeSessions`.

### Headless checks

```sh
.build/debug/ClaudeSessions --scan-test               # parse all transcripts, print stats
.build/debug/ClaudeSessions --summary-test <id-prefix> # test AI summary generation
```

## How it works

| Source | Used for |
|---|---|
| `~/.claude/projects/*/<uuid>.jsonl` | session metadata: custom/AI titles, first prompt, timestamps, message counts, project path, git branch, model |
| `~/.claude/sessions/*.json` | live sessions (PID checked with `kill(pid, 0)`) |
| `claude -p --model haiku` | on-demand summaries (run in an excluded working dir so summary runs never appear as sessions) |

Caches live in `~/Library/Application Support/ClaudeSessions/` (`meta-cache.json`, `summaries.json`, generated `resume/*.command` files).

The app is read-only with respect to your Claude Code data — it never modifies anything under `~/.claude`.
