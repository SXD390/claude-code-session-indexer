#!/usr/bin/env node
'use strict';

/*
 * Reprise — Web
 * ---------------------
 * A zero-dependency, cross-platform local dashboard for browsing, searching,
 * and resuming Claude Code CLI sessions. Node 18+ / stdlib only.
 *
 * SECURITY: binds to 127.0.0.1 only. Your transcripts are private; this server
 * is never exposed to the LAN.
 *
 * Parsing mirrors the native macOS app (Sources/ClaudeSessions/TranscriptScanner.swift):
 * transcripts are line-delimited JSON and we avoid JSON.parse on every line —
 * cheap substring checks decide which lines are worth decoding.
 */

const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const os = require('os');
const { spawn, execFile } = require('child_process');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const HOST = '127.0.0.1';
const DEFAULT_PORT = 4747;

function resolvePort() {
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--port' && argv[i + 1]) return parseInt(argv[i + 1], 10);
    if (a.startsWith('--port=')) return parseInt(a.slice('--port='.length), 10);
  }
  if (process.env.PORT) return parseInt(process.env.PORT, 10);
  return DEFAULT_PORT;
}

const PORT = resolvePort() || DEFAULT_PORT;
const IS_WINDOWS = process.platform === 'win32';
const IS_MAC = process.platform === 'darwin';

const HOME = os.homedir();
const PROJECTS_DIR = path.join(HOME, '.claude', 'projects');
const LIVE_SESSIONS_DIR = path.join(HOME, '.claude', 'sessions');
const PUBLIC_DIR = path.join(__dirname, 'public');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Per-OS application-data directory (matches the platform conventions).
function appDataRoot() {
  if (IS_MAC) return path.join(HOME, 'Library', 'Application Support');
  if (IS_WINDOWS) return process.env.APPDATA || path.join(HOME, 'AppData', 'Roaming');
  return process.env.XDG_CONFIG_HOME || path.join(HOME, '.config');
}

const APP_DATA_DIR = path.join(appDataRoot(), 'claude-sessions');
const SUMMARY_WORK_DIR = path.join(APP_DATA_DIR, 'summary-runs');
const SUMMARIES_FILE = path.join(APP_DATA_DIR, 'summaries.json');
const RESUME_DIR = path.join(APP_DATA_DIR, 'resume');

function ensureDir(dir) {
  try { fs.mkdirSync(dir, { recursive: true }); } catch (_) { /* ignore */ }
}

// The `claude -p` summary runs use SUMMARY_WORK_DIR as their cwd, so Claude Code
// writes their own transcripts into a project dir we must exclude from listings.
// ~/.claude/projects encodes a cwd by replacing every non-alphanumeric with '-'.
function encodeProjectKey(p) {
  return p.replace(/[^A-Za-z0-9]/g, '-');
}

const EXCLUDED_PROJECT_KEYS = new Set([
  encodeProjectKey(SUMMARY_WORK_DIR),
  // Also exclude the native mac app's summary-runs dir if present.
  encodeProjectKey(path.join(appDataRoot(), 'ClaudeSessions', 'summary-runs')),
]);

// ---------------------------------------------------------------------------
// In-memory cache: filePath -> { mtimeMs, size, meta }
// ---------------------------------------------------------------------------

const metaCache = new Map();      // filePath -> { mtimeMs, size, meta }
const sessionIndex = new Map();   // sessionId -> filePath
let summaries = loadSummaries();  // sessionId -> { text, generatedAt }
let hasScannedOnce = false;

function loadSummaries() {
  try {
    const raw = fs.readFileSync(SUMMARIES_FILE, 'utf8');
    const obj = JSON.parse(raw);
    return obj && typeof obj === 'object' ? obj : {};
  } catch (_) {
    return {};
  }
}

function saveSummaries() {
  ensureDir(APP_DATA_DIR);
  try {
    fs.writeFileSync(SUMMARIES_FILE, JSON.stringify(summaries, null, 2));
  } catch (e) {
    console.error('[claude-sessions] Failed to persist summaries:', e.message);
  }
}

// ---------------------------------------------------------------------------
// Transcript parsing (mirrors TranscriptScanner.swift)
// ---------------------------------------------------------------------------

// List every UUID-named transcript with its mtime/size, without reading contents.
async function listTranscripts() {
  let projectDirs;
  try {
    projectDirs = await fsp.readdir(PROJECTS_DIR, { withFileTypes: true });
  } catch (_) {
    return [];
  }
  const result = [];
  for (const dirent of projectDirs) {
    if (!dirent.isDirectory()) continue;
    const key = dirent.name;
    if (EXCLUDED_PROJECT_KEYS.has(key)) continue;
    const dirPath = path.join(PROJECTS_DIR, key);
    let files;
    try {
      files = await fsp.readdir(dirPath, { withFileTypes: true });
    } catch (_) {
      continue;
    }
    for (const f of files) {
      if (!f.isFile()) continue;
      if (!f.name.endsWith('.jsonl')) continue;
      const stem = f.name.slice(0, -'.jsonl'.length);
      if (!UUID_RE.test(stem)) continue; // skip agent-*.jsonl, journal.jsonl, etc.
      const filePath = path.join(dirPath, f.name);
      let st;
      try {
        st = await fsp.stat(filePath);
      } catch (_) {
        continue;
      }
      result.push({ filePath, projectKey: key, sessionId: stem, mtimeMs: st.mtimeMs, size: st.size });
    }
  }
  return result;
}

// Pull "key":"value" out of a JSON line with a plain string scan (unescapes the
// common backslash sequences). Falls back to null on rare escapes.
function extractString(line, key) {
  const needle = '"' + key + '":"';
  const start = line.indexOf(needle);
  if (start < 0) return null;
  let i = start + needle.length;
  let out = '';
  const n = line.length;
  while (i < n) {
    const c = line[i];
    if (c === '\\') {
      const next = line[i + 1];
      if (next === undefined) break;
      switch (next) {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        case '/': out += '/'; break;
        default:
          // Rare escape (\uXXXX): fall back to a full JSON parse for this field.
          try {
            const obj = JSON.parse(line);
            return typeof obj[key] === 'string' ? obj[key] : out;
          } catch (_) { return out; }
      }
      i += 2;
    } else if (c === '"') {
      return out;
    } else {
      out += c;
      i++;
    }
  }
  return out.length ? out : null;
}

// Extract the human text of a user message (string or content-array form).
function userText(obj) {
  const message = obj && obj.message;
  if (!message) return null;
  const content = message.content;
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    const texts = [];
    for (const part of content) {
      if (part && part.type === 'text' && typeof part.text === 'string') texts.push(part.text);
    }
    const joined = texts.join('\n');
    return joined.length ? joined : null;
  }
  return null;
}

function assistantText(obj) {
  const message = obj && obj.message;
  if (!message || !Array.isArray(message.content)) return null;
  const texts = [];
  for (const part of message.content) {
    if (part && part.type === 'text' && typeof part.text === 'string') texts.push(part.text);
  }
  const joined = texts.join('\n').trim();
  return joined.length ? joined : null;
}

// Filter out command wrappers, caveats and other machine-generated "user" text.
function isRealPrompt(text) {
  const t = (text || '').trim();
  if (!t) return false;
  if (t.startsWith('<')) return false;      // <command-name>, <local-command-stdout>, …
  if (t.startsWith('Caveat:')) return false;
  return true;
}

// Full parse of one transcript into a meta object.
async function parseTranscript(entry) {
  const { filePath, projectKey, sessionId, mtimeMs, size } = entry;
  const meta = {
    sessionId,
    transcriptPath: filePath,
    projectKey,
    customTitle: null,
    aiTitle: null,
    firstPrompt: null,
    cwd: null,
    gitBranch: null,
    model: null,
    cliVersion: null,
    createdAt: null,
    lastActivityAt: null,
    userMessageCount: 0,
    assistantMessageCount: 0,
    fileSize: size,
    mtimeMs,
  };

  let content;
  try {
    content = await fsp.readFile(filePath, 'utf8');
  } catch (_) {
    return meta;
  }
  if (!content) {
    meta.lastActivityAt = new Date(mtimeMs).toISOString();
    return meta;
  }

  let firstTimestamp = null;
  let lastTimestamp = null;

  let lineStart = 0;
  const len = content.length;
  for (let idx = 0; idx <= len; idx++) {
    if (idx !== len && content.charCodeAt(idx) !== 10 /* \n */) continue;
    const line = content.slice(lineStart, idx);
    lineStart = idx + 1;
    if (!line) continue;

    if (line.indexOf('"timestamp":"') !== -1) {
      const ts = extractString(line, 'timestamp');
      if (ts) {
        if (firstTimestamp === null) firstTimestamp = ts;
        lastTimestamp = ts;
      }
    }

    if (line.indexOf('"type":"custom-title"') !== -1) {
      try { const o = JSON.parse(line); if (typeof o.customTitle === 'string') meta.customTitle = o.customTitle; } catch (_) {}
      continue;
    }
    if (line.indexOf('"type":"ai-title"') !== -1) {
      try { const o = JSON.parse(line); if (typeof o.aiTitle === 'string') meta.aiTitle = o.aiTitle; } catch (_) {}
      continue;
    }

    // Subagent (sidechain) traffic isn't part of the user's conversation.
    if (line.indexOf('"isSidechain":true') !== -1) continue;

    if (line.indexOf('"type":"assistant"') !== -1) {
      meta.assistantMessageCount++;
      if (meta.model === null && line.indexOf('"model":"') !== -1) {
        const m = extractString(line, 'model');
        if (m) meta.model = m;
      }
      continue;
    }

    if (line.indexOf('"type":"user"') !== -1) {
      if (line.indexOf('"isMeta":true') !== -1 || line.indexOf('"tool_result"') !== -1) continue;
      meta.userMessageCount++;
      if (meta.cwd === null) { const c = extractString(line, 'cwd'); if (c) meta.cwd = c; }
      if (meta.gitBranch === null) { const b = extractString(line, 'gitBranch'); if (b) meta.gitBranch = b; }
      if (meta.cliVersion === null) { const v = extractString(line, 'version'); if (v) meta.cliVersion = v; }
      if (meta.firstPrompt === null) {
        try {
          const o = JSON.parse(line);
          const text = userText(o);
          if (text && isRealPrompt(text)) meta.firstPrompt = text.slice(0, 600);
        } catch (_) {}
      }
      continue;
    }
  }

  meta.createdAt = firstTimestamp;
  meta.lastActivityAt = lastTimestamp || new Date(mtimeMs).toISOString();
  return meta;
}

// Extract user + assistant text messages for the detail-pane preview.
async function extractPreview(filePath, limit = 400, textCap = 1500) {
  let content;
  try {
    content = await fsp.readFile(filePath, 'utf8');
  } catch (_) {
    return [];
  }
  if (!content) return [];

  const messages = [];
  let lineStart = 0;
  const len = content.length;
  for (let idx = 0; idx <= len && messages.length < limit; idx++) {
    if (idx !== len && content.charCodeAt(idx) !== 10) continue;
    const line = content.slice(lineStart, idx);
    lineStart = idx + 1;
    if (!line) continue;

    if (line.indexOf('"isSidechain":true') !== -1) continue;
    const isUser = line.indexOf('"type":"user"') !== -1;
    const isAssistant = line.indexOf('"type":"assistant"') !== -1;
    if (!isUser && !isAssistant) continue;
    if (isUser && (line.indexOf('"isMeta":true') !== -1 || line.indexOf('"tool_result"') !== -1)) continue;

    let obj;
    try { obj = JSON.parse(line); } catch (_) { continue; }
    const ts = typeof obj.timestamp === 'string' ? obj.timestamp : null;

    if (isUser) {
      const text = userText(obj);
      if (text && isRealPrompt(text)) {
        messages.push({ role: 'user', text: text.slice(0, textCap), timestamp: ts });
      }
    } else {
      const text = assistantText(obj);
      if (text) {
        messages.push({ role: 'assistant', text: text.slice(0, textCap), timestamp: ts });
      }
    }
  }
  return messages;
}

// Read live-session descriptors and keep ones whose process is still alive.
async function activeSessions() {
  let files;
  try {
    files = await fsp.readdir(LIVE_SESSIONS_DIR);
  } catch (_) {
    return new Map();
  }
  const map = new Map();
  for (const name of files) {
    if (!name.endsWith('.json')) continue;
    let obj;
    try {
      obj = JSON.parse(await fsp.readFile(path.join(LIVE_SESSIONS_DIR, name), 'utf8'));
    } catch (_) {
      continue;
    }
    const sessionId = obj && obj.sessionId;
    const pid = obj && obj.pid;
    if (!sessionId || typeof pid !== 'number') continue;
    if (!isProcessAlive(pid)) continue;
    map.set(sessionId, {
      sessionId,
      pid,
      name: obj.name || null,
      status: obj.status || null,
      cwd: obj.cwd || null,
    });
  }
  return map;
}

function isProcessAlive(pid) {
  try {
    // Signal 0 probes for existence without actually sending a signal.
    process.kill(pid, 0);
    return true;
  } catch (e) {
    // EPERM means the process exists but we can't signal it — still "alive".
    return e && e.code === 'EPERM';
  }
}

// ---------------------------------------------------------------------------
// Scanning with incremental cache
// ---------------------------------------------------------------------------

async function scanSessions() {
  const listing = await listTranscripts();
  const t0 = Date.now();
  let reparsed = 0;

  // Prune cache entries for files that no longer exist.
  const livePaths = new Set(listing.map((e) => e.filePath));
  for (const key of metaCache.keys()) {
    if (!livePaths.has(key)) metaCache.delete(key);
  }

  const toParse = [];
  for (const entry of listing) {
    const hit = metaCache.get(entry.filePath);
    if (hit && hit.mtimeMs === entry.mtimeMs && hit.size === entry.size) {
      sessionIndex.set(entry.sessionId, entry.filePath);
      continue;
    }
    toParse.push(entry);
  }

  if (!hasScannedOnce) {
    console.log(`[claude-sessions] First scan: ${listing.length} transcripts (${toParse.length} to parse)…`);
  } else if (toParse.length) {
    console.log(`[claude-sessions] Re-scanning ${toParse.length} changed transcript(s)…`);
  }

  // Parse changed/new transcripts with bounded concurrency.
  const CONCURRENCY = 5;
  let cursor = 0;
  async function worker() {
    while (cursor < toParse.length) {
      const entry = toParse[cursor++];
      const meta = await parseTranscript(entry);
      metaCache.set(entry.filePath, { mtimeMs: entry.mtimeMs, size: entry.size, meta });
      sessionIndex.set(entry.sessionId, entry.filePath);
      reparsed++;
      if (!hasScannedOnce && reparsed % 15 === 0) {
        console.log(`[claude-sessions]   parsed ${reparsed}/${toParse.length}…`);
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, toParse.length) }, worker));

  const active = await activeSessions();

  if (toParse.length) {
    console.log(`[claude-sessions] Scan complete: ${reparsed} parsed in ${Date.now() - t0}ms, ${active.size} running.`);
  }
  hasScannedOnce = true;

  // Assemble the API view.
  const sessions = [];
  for (const entry of listing) {
    const cached = metaCache.get(entry.filePath);
    if (!cached) continue;
    sessions.push(toApiSession(cached.meta, active));
  }
  sessions.sort((a, b) => tsValue(b.lastActivityAt) - tsValue(a.lastActivityAt));
  return { sessions, scannedAt: new Date().toISOString() };
}

function tsValue(iso) {
  if (!iso) return -Infinity;
  const t = Date.parse(iso);
  return Number.isNaN(t) ? -Infinity : t;
}

function displayTitle(meta) {
  if (meta.customTitle && meta.customTitle.length) return meta.customTitle;
  if (meta.aiTitle && meta.aiTitle.length) return meta.aiTitle;
  if (meta.firstPrompt && meta.firstPrompt.length) {
    const line = meta.firstPrompt.split('\n')[0];
    return line.length > 80 ? line.slice(0, 80) + '…' : line;
  }
  return meta.sessionId.slice(0, 8);
}

function projectDisplayName(meta) {
  if (meta.cwd && meta.cwd.length) return path.basename(meta.cwd);
  return meta.projectKey;
}

function resumeCommandFor(meta) {
  const cd = IS_WINDOWS ? 'cd /d' : 'cd';
  if (meta.cwd && meta.cwd.length) {
    return `${cd} "${meta.cwd}" && claude --resume ${meta.sessionId}`;
  }
  return `claude --resume ${meta.sessionId}`;
}

function toApiSession(meta, active) {
  const stored = summaries[meta.sessionId];
  return {
    sessionId: meta.sessionId,
    projectKey: meta.projectKey,
    projectName: projectDisplayName(meta),
    cwd: meta.cwd,
    title: displayTitle(meta),
    customTitle: meta.customTitle,
    aiTitle: meta.aiTitle,
    firstPrompt: meta.firstPrompt,
    createdAt: meta.createdAt,
    lastActivityAt: meta.lastActivityAt,
    userMessageCount: meta.userMessageCount,
    assistantMessageCount: meta.assistantMessageCount,
    gitBranch: meta.gitBranch,
    model: meta.model,
    cliVersion: meta.cliVersion,
    fileSize: meta.fileSize,
    running: active.has(meta.sessionId),
    summary: stored ? { text: stored.text, generatedAt: stored.generatedAt } : null,
    resumeCommand: resumeCommandFor(meta),
  };
}

// Locate a transcript by session id, ensuring meta is available (parse on demand).
async function getSessionMeta(sessionId) {
  let filePath = sessionIndex.get(sessionId);
  if (!filePath || !fs.existsSync(filePath)) {
    // Re-list to find it (readdir only — cheap).
    const listing = await listTranscripts();
    const match = listing.find((e) => e.sessionId === sessionId);
    if (!match) return null;
    filePath = match.filePath;
    sessionIndex.set(sessionId, filePath);
    const cached = metaCache.get(filePath);
    if (cached && cached.mtimeMs === match.mtimeMs && cached.size === match.size) return cached.meta;
    const meta = await parseTranscript(match);
    metaCache.set(filePath, { mtimeMs: match.mtimeMs, size: match.size, meta });
    return meta;
  }
  const cached = metaCache.get(filePath);
  if (cached) {
    // Validate against current mtime/size.
    try {
      const st = fs.statSync(filePath);
      if (st.mtimeMs === cached.mtimeMs && st.size === cached.size) return cached.meta;
      const meta = await parseTranscript({ filePath, projectKey: cached.meta.projectKey, sessionId, mtimeMs: st.mtimeMs, size: st.size });
      metaCache.set(filePath, { mtimeMs: st.mtimeMs, size: st.size, meta });
      return meta;
    } catch (_) {
      return cached.meta;
    }
  }
  // No cache — parse fresh.
  try {
    const st = fs.statSync(filePath);
    const meta = await parseTranscript({ filePath, projectKey: path.basename(path.dirname(filePath)), sessionId, mtimeMs: st.mtimeMs, size: st.size });
    metaCache.set(filePath, { mtimeMs: st.mtimeMs, size: st.size, meta });
    return meta;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// AI summary generation (spawns `claude -p`)
// ---------------------------------------------------------------------------

const SUMMARY_INSTRUCTION =
  'The stdin contains an excerpt of a Claude Code CLI coding session transcript. ' +
  'Write a summary of the session: first 1-2 plain sentences stating the goal and what was accomplished, ' +
  "then up to 3 short bullet points (starting with '- ') of key outcomes or decisions. " +
  'No preamble, no headers, under 110 words total.';

let cachedClaudePath; // resolved once, lazily

function resolveClaudePath() {
  if (cachedClaudePath !== undefined) return Promise.resolve(cachedClaudePath);
  return new Promise((resolve) => {
    if (IS_WINDOWS) {
      execFile('where', ['claude'], { timeout: 8000 }, (err, stdout) => {
        const p = !err && stdout ? stdout.split(/\r?\n/)[0].trim() : '';
        cachedClaudePath = p || null;
        resolve(cachedClaudePath);
      });
    } else {
      const shell = IS_MAC ? '/bin/zsh' : (fs.existsSync('/bin/bash') ? '/bin/bash' : '/bin/sh');
      execFile(shell, ['-lc', 'command -v claude'], { timeout: 8000 }, (err, stdout) => {
        const p = !err && stdout ? stdout.trim() : '';
        cachedClaudePath = p || null;
        resolve(cachedClaudePath);
      });
    }
  });
}

async function buildExcerpt(meta) {
  const messages = await extractPreview(meta.transcriptPath, 400, 1500);
  if (!messages.length) return '';

  const parts = [];
  parts.push('Project: ' + projectDisplayName(meta));
  if (meta.customTitle) parts.push('User-assigned session name: ' + meta.customTitle);
  if (meta.aiTitle) parts.push('Session title: ' + meta.aiTitle);
  parts.push('---');

  let budget = 14000;
  const userMessages = messages.filter((m) => m.role === 'user').slice(0, 50);
  for (const m of userMessages) {
    const snippet = 'USER: ' + m.text.slice(0, 400);
    budget -= snippet.length;
    if (budget < 2000) break;
    parts.push(snippet);
  }

  // Close with the tail of the conversation so the summary reflects the outcome.
  let lastAssistant = null;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'assistant') { lastAssistant = messages[i]; break; }
  }
  if (lastAssistant) {
    parts.push('---');
    parts.push('FINAL ASSISTANT MESSAGE: ' + lastAssistant.text.slice(0, 1500));
  }
  return parts.join('\n');
}

async function generateSummary(meta) {
  const claude = await resolveClaudePath();
  if (!claude) {
    const err = new Error('Could not find the `claude` CLI on your PATH.');
    err.code = 'CLAUDE_NOT_FOUND';
    throw err;
  }
  const excerpt = await buildExcerpt(meta);
  if (!excerpt) {
    const err = new Error('This session has no conversation content to summarize.');
    err.code = 'EMPTY_TRANSCRIPT';
    throw err;
  }

  ensureDir(SUMMARY_WORK_DIR);

  return new Promise((resolve, reject) => {
    const env = Object.assign({}, process.env, { CLAUDE_CODE_DISABLE_AUTOUPDATE: '1' });
    const child = spawn(claude, ['-p', SUMMARY_INSTRUCTION, '--model', 'haiku'], {
      cwd: SUMMARY_WORK_DIR,
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let out = '';
    let errOut = '';
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      try { child.kill('SIGTERM'); } catch (_) {}
      const err = new Error('Timed out after 3 minutes.');
      err.code = 'TIMEOUT';
      reject(err);
    }, 180000);

    child.stdout.on('data', (d) => { out += d.toString('utf8'); });
    child.stderr.on('data', (d) => { errOut += d.toString('utf8'); });

    child.on('error', (e) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(e);
    });

    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const text = out.trim();
      if (code !== 0) {
        const err = new Error((errOut.trim() || `claude exited with status ${code}`).slice(0, 300));
        err.code = 'PROCESS_FAILED';
        return reject(err);
      }
      if (!text) {
        const err = new Error('claude returned no output.');
        err.code = 'PROCESS_FAILED';
        return reject(err);
      }
      resolve(text);
    });

    try {
      child.stdin.write(excerpt);
      child.stdin.end();
    } catch (_) { /* handled by 'error' */ }
  });
}

// ---------------------------------------------------------------------------
// Resume in terminal
// ---------------------------------------------------------------------------

function shellQuoteSingle(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function sanitizeFileName(s) {
  return String(s || '').replace(/[^A-Za-z0-9 _-]/g, '').trim().slice(0, 40);
}

// Resolve an executable on PATH synchronously (spawn's ENOENT is async, so a
// try/catch around spawn can't tell us whether a terminal emulator exists).
function whichSync(cmd) {
  const dirs = (process.env.PATH || '').split(path.delimiter);
  for (const d of dirs) {
    if (!d) continue;
    const p = path.join(d, cmd);
    try { fs.accessSync(p, fs.constants.X_OK); return p; } catch (_) { /* keep looking */ }
  }
  return null;
}

function resumeInTerminal(meta) {
  const cwd = meta.cwd || '';
  const id = meta.sessionId;

  if (IS_MAC) {
    // Write an executable .command file and `open` it — no Automation prompt.
    ensureDir(RESUME_DIR);
    const base = sanitizeFileName(displayTitle(meta)) || id.slice(0, 8);
    const scriptPath = path.join(RESUME_DIR, base + '.command');
    let script = '#!/bin/zsh\n';
    if (cwd) script += 'cd ' + shellQuoteSingle(cwd) + ' || exit 1\n';
    script += 'exec claude --resume ' + id + '\n';
    fs.writeFileSync(scriptPath, script);
    fs.chmodSync(scriptPath, 0o755);
    const child = spawn('open', [scriptPath], { detached: true, stdio: 'ignore' });
    child.unref();
    return;
  }

  if (IS_WINDOWS) {
    // Open a new console window that stays open (cmd /k) in the session's cwd.
    // We use start's own /D flag to set the working directory instead of a
    // `cd /d "..." && ...` chain — the && would otherwise bind to the outer
    // shell, and nested quotes around a path with spaces are fragile.
    // windowsVerbatimArguments keeps our quoting intact.
    const args = ['/c', 'start', '""'];
    if (cwd) args.push('/D', '"' + cwd + '"');
    args.push('cmd', '/k', 'claude --resume ' + id);
    const child = spawn('cmd', args, {
      detached: true,
      stdio: 'ignore',
      windowsVerbatimArguments: true,
    });
    child.unref();
    return;
  }

  // Linux: launch the first terminal emulator that actually exists on PATH.
  const inner = (cwd ? 'cd ' + shellQuoteSingle(cwd) + ' && ' : '') + 'exec claude --resume ' + id;
  const candidates = [
    ['x-terminal-emulator', ['-e', 'sh', '-c', inner]],
    ['gnome-terminal', ['--', 'sh', '-c', inner]],
    ['konsole', ['-e', 'sh', '-c', inner]],
    ['xterm', ['-e', 'sh', '-c', inner]],
  ];
  for (const [cmd, args] of candidates) {
    const bin = whichSync(cmd);
    if (!bin) continue;
    const child = spawn(bin, args, { detached: true, stdio: 'ignore' });
    child.unref();
    return;
  }
  throw new Error('No supported terminal emulator found (tried x-terminal-emulator, gnome-terminal, konsole, xterm).');
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
};

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => { data += c; if (data.length > 1e6) req.destroy(); });
    req.on('end', () => resolve(data));
    req.on('error', () => resolve(''));
  });
}

async function serveStatic(req, res, pathname) {
  let rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const filePath = path.join(PUBLIC_DIR, rel);
  // Prevent path traversal.
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }
  let st;
  try {
    st = await fsp.stat(filePath);
  } catch (_) {
    res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('Not found'); return;
  }
  if (st.isDirectory()) { res.writeHead(404); res.end('Not found'); return; }
  const ext = path.extname(filePath).toLowerCase();
  const type = MIME[ext] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' });
  fs.createReadStream(filePath).pipe(res);
}

const server = http.createServer(async (req, res) => {
  // WHATWG URL API (url.parse is deprecated); host is irrelevant for routing.
  const parsed = new URL(req.url, 'http://127.0.0.1');
  let pathname;
  try { pathname = decodeURIComponent(parsed.pathname); } catch (_) { pathname = parsed.pathname; }
  const method = req.method;

  try {
    // --- API routes ---
    if (pathname === '/api/sessions' && method === 'GET') {
      const data = await scanSessions();
      return sendJson(res, 200, data);
    }

    const previewMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/preview$/);
    if (previewMatch && method === 'GET') {
      const id = previewMatch[1];
      const meta = await getSessionMeta(id);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      const messages = await extractPreview(meta.transcriptPath, 400, 1500);
      return sendJson(res, 200, { messages });
    }

    const summaryMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/summary$/);
    if (summaryMatch && method === 'POST') {
      const id = summaryMatch[1];
      const meta = await getSessionMeta(id);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      try {
        const text = await generateSummary(meta);
        const generatedAt = new Date().toISOString();
        summaries[id] = { text, generatedAt };
        saveSummaries();
        return sendJson(res, 200, { text, generatedAt });
      } catch (e) {
        console.error('[claude-sessions] Summary failed:', e.message);
        return sendJson(res, 500, { error: e.message, code: e.code || 'ERROR' });
      }
    }

    const resumeMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/resume$/);
    if (resumeMatch && method === 'POST') {
      const id = resumeMatch[1];
      const meta = await getSessionMeta(id);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      try {
        resumeInTerminal(meta);
        return sendJson(res, 200, { ok: true });
      } catch (e) {
        console.error('[claude-sessions] Resume failed:', e.message);
        return sendJson(res, 500, { error: e.message });
      }
    }

    if (pathname.startsWith('/api/')) {
      return sendJson(res, 404, { error: 'Unknown endpoint' });
    }

    // --- Static assets ---
    if (method === 'GET' || method === 'HEAD') {
      return await serveStatic(req, res, pathname);
    }

    res.writeHead(405); res.end('Method not allowed');
  } catch (e) {
    console.error('[claude-sessions] Request error:', e && e.stack ? e.stack : e);
    if (!res.headersSent) sendJson(res, 500, { error: 'Internal server error' });
    else res.end();
  }
});

server.listen(PORT, HOST, () => {
  ensureDir(APP_DATA_DIR);
  console.log('');
  console.log('  Reprise — Web');
  console.log('  ---------------------');
  console.log(`  Local dashboard:  http://${HOST}:${PORT}`);
  console.log(`  Projects dir:     ${PROJECTS_DIR}`);
  console.log(`  App data:         ${APP_DATA_DIR}`);
  console.log('  Bound to 127.0.0.1 only — your transcripts stay private.');
  console.log('  Press Ctrl+C to stop.');
  console.log('');
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`\n[claude-sessions] Port ${PORT} is already in use.`);
    console.error(`Set a different one with:  PORT=4848 node server.js  (or  --port 4848)\n`);
  } else {
    console.error('[claude-sessions] Server error:', e.message);
  }
  process.exit(1);
});
