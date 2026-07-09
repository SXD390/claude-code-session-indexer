#!/usr/bin/env node
'use strict';

/*
 * Claude Code Session Indexer — Web
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
// CSI_CLAUDE_DIR points the indexer at an alternate data root (demos, tests).
const CLAUDE_ROOT = process.env.CSI_CLAUDE_DIR || path.join(HOME, '.claude');
const PROJECTS_DIR = path.join(CLAUDE_ROOT, 'projects');
const LIVE_SESSIONS_DIR = path.join(CLAUDE_ROOT, 'sessions');
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
const BRIEFS_FILE = path.join(APP_DATA_DIR, 'briefs.json');
const HANDOFFS_FILE = path.join(APP_DATA_DIR, 'handoffs.json');
const RESUME_DIR = path.join(APP_DATA_DIR, 'resume');

// ---------------------------------------------------------------------------
// Usage / cost model (see analytics spec — must match the macOS implementation)
// ---------------------------------------------------------------------------

// Pricing table, USD per million tokens: [prefix, input, output, cacheRead, cacheWrite].
// Matched by model-id PREFIX, first match wins (order matters).
const PRICING = [
  ['claude-fable-5', 10.0, 50.0, 1.00, 12.50],
  ['claude-mythos',  10.0, 50.0, 1.00, 12.50],
  ['claude-opus-4-1', 15.0, 75.0, 1.50, 18.75],
  ['claude-opus-4-0', 15.0, 75.0, 1.50, 18.75],
  ['claude-opus',      5.0, 25.0, 0.50,  6.25],
  ['claude-sonnet',    3.0, 15.0, 0.30,  3.75],
  ['claude-haiku',     1.0,  5.0, 0.10,  1.25],
];
const FALLBACK_PRICE = [3.0, 15.0, 0.30, 3.75]; // unknown models

function rateFor(model) {
  const m = model || '';
  for (const r of PRICING) if (m.indexOf(r[0]) === 0) return r;
  return ['(other)', FALLBACK_PRICE[0], FALLBACK_PRICE[1], FALLBACK_PRICE[2], FALLBACK_PRICE[3]];
}

// Coarse tier for the "model mix" insight.
function modelTier(model) {
  const m = model || '';
  if (m.indexOf('claude-fable') === 0 || m.indexOf('claude-mythos') === 0) return 'Fable';
  if (m.indexOf('claude-opus') === 0) return 'Opus';
  if (m.indexOf('claude-sonnet') === 0) return 'Sonnet';
  if (m.indexOf('claude-haiku') === 0) return 'Haiku';
  return 'Other';
}

// Local-timezone day key (YYYY-MM-DD). Server + native app share a machine/tz,
// so day attribution matches. String order == chronological order.
function localDayKey(epoch) {
  const d = new Date(epoch);
  const mo = String(d.getMonth() + 1).padStart(2, '0');
  const da = String(d.getDate()).padStart(2, '0');
  return d.getFullYear() + '-' + mo + '-' + da;
}

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

const metaCache = new Map();      // filePath -> { mtimeMs, size, meta }  (meta.usage carries analytics)
const sessionIndex = new Map();   // sessionId -> filePath
let summaries = loadSummaries();  // sessionId -> { text, generatedAt }
let briefs = loadBriefs();        // sessionId -> { state, open, nextPrompt, generatedAt, sessionLastActivity }
let handoffs = loadHandoffs();    // sessionId -> { progress, claudeSection, kickstart, raw, generatedAt, sessionLastActivity, cwd, project }
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

function loadBriefs() {
  try {
    const obj = JSON.parse(fs.readFileSync(BRIEFS_FILE, 'utf8'));
    return obj && typeof obj === 'object' ? obj : {};
  } catch (_) {
    return {};
  }
}

function saveBriefs() {
  ensureDir(APP_DATA_DIR);
  try {
    fs.writeFileSync(BRIEFS_FILE, JSON.stringify(briefs, null, 2));
  } catch (e) {
    console.error('[claude-sessions] Failed to persist briefs:', e.message);
  }
}

function loadHandoffs() {
  try {
    const obj = JSON.parse(fs.readFileSync(HANDOFFS_FILE, 'utf8'));
    return obj && typeof obj === 'object' ? obj : {};
  } catch (_) {
    return {};
  }
}

function saveHandoffs() {
  ensureDir(APP_DATA_DIR);
  try {
    fs.writeFileSync(HANDOFFS_FILE, JSON.stringify(handoffs, null, 2));
  } catch (e) {
    console.error('[claude-sessions] Failed to persist handoffs:', e.message);
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

  // --- usage / analytics accumulators (dedup by message.id, INCLUDE sidechains) ---
  const stamps = [];                 // epoch ms of every timestamped line (heartbeat)
  const seenUsage = new Set();       // message.id / requestId dedup
  const days = new Map();            // dayKey -> per-day aggregate bucket
  const byModelAll = new Map();      // model -> all-time aggregate for this session
  const uTotals = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, activeSeconds: 0, savings: 0 };
  function dayBucket(key) {
    let b = days.get(key);
    if (!b) { b = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, active: 0, savings: 0, hours: {}, models: {} }; days.set(key, b); }
    return b;
  }

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
        const e = Date.parse(ts);
        if (!Number.isNaN(e)) stamps.push(e);
      }
    }

    // Usage: any assistant line carrying a usage block (sidechains INCLUDED — the
    // tokens were really spent). Deduped by message.id across streaming chunks.
    if (line.indexOf('"usage"') !== -1 && line.indexOf('"type":"assistant"') !== -1) {
      let uo = null;
      try { uo = JSON.parse(line); } catch (_) { uo = null; }
      const um = uo && uo.message;
      const usage = um && um.usage;
      if (usage) {
        const uid = um.id || uo.requestId || line;
        if (!seenUsage.has(uid)) {
          seenUsage.add(uid);
          const inp = usage.input_tokens || 0;
          const out = usage.output_tokens || 0;
          const cr = usage.cache_read_input_tokens || 0;
          const cw = usage.cache_creation_input_tokens || 0;
          const r = rateFor(um.model);
          const cost = (inp * r[1] + out * r[2] + cr * r[3] + cw * r[4]) / 1e6;
          const savings = (cr * (r[1] - r[3])) / 1e6; // vs paying full input rate
          const te = typeof uo.timestamp === 'string' ? Date.parse(uo.timestamp) : NaN;
          const epoch = Number.isNaN(te) ? mtimeMs : te;
          const dk = localDayKey(epoch);
          const hr = new Date(epoch).getHours();
          const model = um.model || '(unknown)';
          const b = dayBucket(dk);
          b.input += inp; b.output += out; b.cacheRead += cr; b.cacheWrite += cw; b.cost += cost; b.savings += savings;
          b.hours[hr] = (b.hours[hr] || 0) + 1;
          let dm = b.models[model];
          if (!dm) { dm = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, count: 0 }; b.models[model] = dm; }
          dm.input += inp; dm.output += out; dm.cacheRead += cr; dm.cacheWrite += cw; dm.cost += cost; dm.count++;
          let am = byModelAll.get(model);
          if (!am) { am = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, count: 0 }; byModelAll.set(model, am); }
          am.input += inp; am.output += out; am.cacheRead += cr; am.cacheWrite += cw; am.cost += cost; am.count++;
          uTotals.input += inp; uTotals.output += out; uTotals.cacheRead += cr; uTotals.cacheWrite += cw;
          uTotals.cost += cost; uTotals.savings += savings;
        }
      }
      // fall through: the assistant-count branch below still runs for non-sidechain lines
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

  // Heartbeat active time: sum gaps <= 300s between consecutive timestamps,
  // attributed to the earlier timestamp's day, plus a fixed 60s tail per session.
  stamps.sort((a, b) => a - b);
  for (let i = 1; i < stamps.length; i++) {
    const g = (stamps[i] - stamps[i - 1]) / 1000;
    if (g > 0 && g <= 300) {
      dayBucket(localDayKey(stamps[i - 1])).active += g;
      uTotals.activeSeconds += g;
    }
  }
  if (stamps.length) {
    dayBucket(localDayKey(stamps[stamps.length - 1])).active += 60;
    uTotals.activeSeconds += 60;
  }

  meta.usage = {
    totals: uTotals,
    byModelAll: Array.from(byModelAll, ([model, v]) => Object.assign({ model }, v)).sort((a, b) => b.cost - a.cost),
    days: Object.fromEntries(days),
    firstMs: stamps.length ? stamps[0] : (firstTimestamp ? Date.parse(firstTimestamp) : null),
    lastMs: stamps.length ? stamps[stamps.length - 1] : null,
  };
  return meta;
}

// Aggregate cached per-session usage records over a local-day range (inclusive).
// fromDay / toDay are 'YYYY-MM-DD' strings or null (open-ended). Returns the shape
// consumed by GET /api/usage.
function aggregateUsage(fromDay, toDay) {
  const tokens = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  let totalCost = 0, totalActive = 0, totalSavings = 0;
  const dailyMap = new Map();
  const modelMap = new Map();
  const projMap = new Map();
  const hours = new Array(24).fill(0);
  let longest = null, expensive = null;

  for (const cached of metaCache.values()) {
    const meta = cached.meta;
    const u = meta && meta.usage;
    if (!u || !u.days) continue;
    let sCost = 0, sActive = 0, touched = false;
    for (const dk in u.days) {
      if (fromDay && dk < fromDay) continue;
      if (toDay && dk > toDay) continue;
      const d = u.days[dk];
      touched = true;
      tokens.input += d.input; tokens.output += d.output; tokens.cacheRead += d.cacheRead; tokens.cacheWrite += d.cacheWrite;
      totalCost += d.cost; totalActive += d.active; totalSavings += d.savings;
      sCost += d.cost; sActive += d.active;

      let dm = dailyMap.get(dk);
      if (!dm) { dm = { date: dk, activeSeconds: 0, cost: 0, tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, sessions: new Set() }; dailyMap.set(dk, dm); }
      dm.activeSeconds += d.active; dm.cost += d.cost;
      dm.tokens.input += d.input; dm.tokens.output += d.output; dm.tokens.cacheRead += d.cacheRead; dm.tokens.cacheWrite += d.cacheWrite;
      dm.sessions.add(meta.sessionId);

      for (const h in d.hours) hours[+h] += d.hours[h];
      for (const mk in d.models) {
        const mm = d.models[mk];
        let g = modelMap.get(mk);
        if (!g) { g = { model: mk, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, count: 0 }; modelMap.set(mk, g); }
        g.input += mm.input; g.output += mm.output; g.cacheRead += mm.cacheRead; g.cacheWrite += mm.cacheWrite; g.cost += mm.cost; g.count += mm.count;
      }
    }
    if (touched) {
      const proj = projectDisplayName(meta);
      let pg = projMap.get(proj);
      if (!pg) { pg = { project: proj, activeSeconds: 0, cost: 0, sessions: 0 }; projMap.set(proj, pg); }
      pg.activeSeconds += sActive; pg.cost += sCost; pg.sessions++;
      if (!longest || sActive > longest.seconds) longest = { id: meta.sessionId, title: displayTitle(meta), seconds: sActive };
      if (!expensive || sCost > expensive.cost) expensive = { id: meta.sessionId, title: displayTitle(meta), cost: sCost };
    }
  }

  const daily = Array.from(dailyMap.values())
    .map((d) => ({ date: d.date, activeSeconds: d.activeSeconds, cost: d.cost, tokens: d.tokens, sessions: d.sessions.size }))
    .sort((a, b) => (a.date < b.date ? -1 : 1));
  const byModel = Array.from(modelMap.values()).sort((a, b) => b.cost - a.cost);
  const byProject = Array.from(projMap.values()).sort((a, b) => b.activeSeconds - a.activeSeconds);

  const cacheDenom = tokens.input + tokens.cacheRead;
  const activeHours = totalActive / 3600;
  const tierOut = {};
  let tierTotal = 0;
  for (const m of byModel) { const t = modelTier(m.model); tierOut[t] = (tierOut[t] || 0) + m.output; tierTotal += m.output; }

  return {
    totals: { activeSeconds: totalActive, cost: totalCost, tokens },
    daily,
    byModel,
    byProject,
    hourHistogram: hours,
    insights: {
      cacheHitRate: cacheDenom > 0 ? tokens.cacheRead / cacheDenom : 0,
      cacheSavings: totalSavings,
      costPerActiveHour: activeHours > 0 ? totalCost / activeHours : 0,
      longestSession: longest,
      mostExpensiveSession: expensive,
      modelMix: { tiers: tierOut, total: tierTotal },
    },
  };
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
  const brief = briefs[meta.sessionId] || null;
  const handoff = handoffs[meta.sessionId] || null;
  const ut = meta.usage ? meta.usage.totals : null;
  const usage = ut
    ? { tokens: { input: ut.input, output: ut.output, cacheRead: ut.cacheRead, cacheWrite: ut.cacheWrite }, cost: ut.cost, activeSeconds: ut.activeSeconds }
    : null;
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
    usage,
    brief: brief
      ? { state: brief.state, open: brief.open || [], nextPrompt: brief.nextPrompt, generatedAt: brief.generatedAt, sessionLastActivity: brief.sessionLastActivity || null }
      : null,
    // Light stub only — the full handoff content is lazy-loaded via GET /handoff so
    // the /api/sessions payload stays lean.
    handoff: handoff
      ? { generatedAt: handoff.generatedAt, sessionLastActivity: handoff.sessionLastActivity || null, hasClaudeSection: !!handoff.claudeSection }
      : null,
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

// Shared `claude -p` runner: resolves the CLI, pipes the excerpt on stdin, and
// returns the trimmed stdout. Used by both summaries and pickup briefs so their
// discovery / cwd / timeout behaviour is identical.
async function runClaude(instruction, excerpt) {
  const claude = await resolveClaudePath();
  if (!claude) {
    const err = new Error('Could not find the `claude` CLI on your PATH.');
    err.code = 'CLAUDE_NOT_FOUND';
    throw err;
  }
  ensureDir(SUMMARY_WORK_DIR);

  return new Promise((resolve, reject) => {
    const env = Object.assign({}, process.env, { CLAUDE_CODE_DISABLE_AUTOUPDATE: '1' });
    const child = spawn(claude, ['-p', instruction, '--model', 'haiku'], {
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

async function generateSummary(meta) {
  const excerpt = await buildExcerpt(meta);
  if (!excerpt) {
    const err = new Error('This session has no conversation content to summarize.');
    err.code = 'EMPTY_TRANSCRIPT';
    throw err;
  }
  return runClaude(SUMMARY_INSTRUCTION, excerpt);
}

// ---------------------------------------------------------------------------
// Pickup Brief generation (hero continuity feature)
// ---------------------------------------------------------------------------

const BRIEF_INSTRUCTION =
  'The stdin contains the tail of a Claude Code session transcript. Produce a pickup brief ' +
  'for resuming this work, in exactly this format:\n' +
  'STATE: 2-3 plain sentences on where the work stands (what was completed, what was in progress when the session ended).\n' +
  "OPEN: up to 4 bullets (- ) of unresolved threads, known bugs, or explicitly deferred TODOs. Write 'none' if clean.\n" +
  'NEXT PROMPT: a single ready-to-paste prompt (2-5 sentences, imperative, self-contained — assume the resumed ' +
  'session has full prior context) that would continue the work most productively.';

// Titles + first prompt + last 30 user/assistant messages (each truncated to
// 500 chars) + file paths mentioned in the final assistant message. ~14KB cap.
async function buildBriefExcerpt(meta) {
  const messages = await extractPreview(meta.transcriptPath, 1000, 2000);
  if (!messages.length) return '';

  const parts = [];
  parts.push('Project: ' + projectDisplayName(meta));
  if (meta.customTitle) parts.push('Session name: ' + meta.customTitle);
  if (meta.aiTitle) parts.push('Session title: ' + meta.aiTitle);
  const first = messages.find((m) => m.role === 'user');
  if (first) parts.push('First prompt: ' + first.text.slice(0, 500));

  parts.push('--- LAST 30 MESSAGES ---');
  for (const m of messages.slice(-30)) {
    parts.push((m.role === 'user' ? 'USER: ' : 'ASSISTANT: ') + m.text.slice(0, 500));
  }

  let lastAssistant = null;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'assistant') { lastAssistant = messages[i]; break; }
  }
  if (lastAssistant) {
    const paths = (lastAssistant.text.match(/[A-Za-z0-9_./~-]*\/[A-Za-z0-9_./~-]+\.[A-Za-z0-9]{1,6}/g) || [])
      .concat(lastAssistant.text.match(/\b[A-Za-z0-9_-]+\.(?:swift|js|ts|tsx|jsx|py|go|rs|java|rb|css|html|json|md|sh|yml|yaml|c|cpp|h)\b/g) || []);
    const uniq = Array.from(new Set(paths)).slice(0, 12);
    if (uniq.length) parts.push('Files referenced: ' + uniq.join(', '));
  }

  let out = parts.join('\n');
  if (out.length > 14000) out = out.slice(0, 14000);
  return out;
}

// Split the model's response into STATE / OPEN / NEXT PROMPT sections.
function parseBrief(raw) {
  const markers = [['state', /STATE\s*:/i], ['open', /OPEN\s*:/i], ['next', /NEXT\s*PROMPT\s*:/i]];
  const found = [];
  for (const [key, re] of markers) { const m = raw.match(re); if (m) found.push({ key, start: m.index, after: m.index + m[0].length }); }
  found.sort((a, b) => a.start - b.start);
  const sec = {};
  for (let i = 0; i < found.length; i++) {
    const cur = found[i], next = found[i + 1];
    sec[cur.key] = raw.slice(cur.after, next ? next.start : raw.length).trim();
  }
  const state = (sec.state || raw).trim();
  let open = [];
  if (sec.open) {
    const t = sec.open.trim();
    if (!/^none\.?$/i.test(t)) {
      open = t.split('\n').map((l) => l.replace(/^[-*•]\s*/, '').trim()).filter(Boolean);
    }
  }
  const nextPrompt = (sec.next || '').trim();
  return { state, open, nextPrompt };
}

async function generateBrief(meta) {
  const excerpt = await buildBriefExcerpt(meta);
  if (!excerpt) {
    const err = new Error('This session has no conversation content to brief from.');
    err.code = 'EMPTY_TRANSCRIPT';
    throw err;
  }
  const raw = await runClaude(BRIEF_INSTRUCTION, excerpt);
  const parsed = parseBrief(raw);
  parsed.raw = raw;
  parsed.generatedAt = new Date().toISOString();
  return parsed;
}

// ---------------------------------------------------------------------------
// Handoff generation (writes PROGRESS.md / CLAUDE.md into the session's cwd so a
// brand-new Claude Code session can pick up the old session's work)
// ---------------------------------------------------------------------------

// Markers that fence the block we own inside a project's CLAUDE.md, so repeated
// writes replace-in-place instead of piling up duplicates.
const HANDOFF_CLAUDE_START = '<!-- session-indexer:handoff:start -->';
const HANDOFF_CLAUDE_END = '<!-- session-indexer:handoff:end -->';

// The model must return EXACTLY this delimited shape; we split it into three parts.
function handoffInstruction(dateStr) {
  return (
    'The stdin contains the tail of a Claude Code CLI coding session transcript. ' +
    'Produce a HANDOFF so a brand-new Claude Code session can pick up this work. ' +
    'Base everything strictly on the transcript — do not invent facts. ' +
    'Output EXACTLY the following, with these literal delimiter lines, and nothing before or after:\n' +
    '===PROGRESS===\n' +
    'A dated progress section in GitHub-flavored markdown. Its first line MUST be exactly:\n' +
    '## ' + dateStr + ' — <short session title>\n' +
    'Then these subsections in order, each a bold label on its own line followed by bullet points (lines starting with "- "):\n' +
    '**Done**\n**In progress**\n**Open threads**\n**Key decisions**\n**Files touched**\n**How to verify**\n' +
    'Under any subsection with nothing to report, write a single "- none" bullet. Keep bullets concise.\n' +
    '===CLAUDE===\n' +
    'Durable project knowledge for FUTURE Claude sessions in this repo: build / run / test commands actually observed in the transcript, ' +
    'project structure, conventions, and gotchas. This is NOT session status — no dates, no to-dos, no "we did X". ' +
    'If there is nothing durable and reusable to record, output exactly NONE and nothing else in this part.\n' +
    '===KICKSTART===\n' +
    'A single ready-to-paste prompt of 3 to 6 sentences (imperative, self-contained) for a fresh Claude Code session: ' +
    'tell it to read PROGRESS.md and CLAUDE.md in this directory, state the immediate goal drawn from the open threads, ' +
    'and say how to verify success.\n' +
    '===END==='
  );
}

// Titles + first prompt + last ~50 user/assistant messages (each truncated to
// 500 chars) + file paths mentioned in the final assistant message. ~16KB cap.
async function buildHandoffExcerpt(meta) {
  const messages = await extractPreview(meta.transcriptPath, 1000, 2000);
  if (!messages.length) return '';

  const parts = [];
  parts.push('Project: ' + projectDisplayName(meta));
  if (meta.cwd) parts.push('Project directory: ' + meta.cwd);
  if (meta.gitBranch) parts.push('Git branch: ' + meta.gitBranch);
  if (meta.customTitle) parts.push('Session name: ' + meta.customTitle);
  if (meta.aiTitle) parts.push('Session title: ' + meta.aiTitle);
  const first = messages.find((m) => m.role === 'user');
  if (first) parts.push('First prompt: ' + first.text.slice(0, 500));

  parts.push('--- LAST 50 MESSAGES ---');
  for (const m of messages.slice(-50)) {
    parts.push((m.role === 'user' ? 'USER: ' : 'ASSISTANT: ') + m.text.slice(0, 500));
  }

  let lastAssistant = null;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'assistant') { lastAssistant = messages[i]; break; }
  }
  if (lastAssistant) {
    const paths = (lastAssistant.text.match(/[A-Za-z0-9_./~-]*\/[A-Za-z0-9_./~-]+\.[A-Za-z0-9]{1,6}/g) || [])
      .concat(lastAssistant.text.match(/\b[A-Za-z0-9_-]+\.(?:swift|js|ts|tsx|jsx|py|go|rs|java|rb|css|html|json|md|sh|yml|yaml|c|cpp|h)\b/g) || []);
    const uniq = Array.from(new Set(paths)).slice(0, 12);
    if (uniq.length) parts.push('Files referenced: ' + uniq.join(', '));
  }

  let out = parts.join('\n');
  if (out.length > 16000) out = out.slice(0, 16000);
  return out;
}

// Split the model's response into PROGRESS / CLAUDE / KICKSTART parts. A CLAUDE
// part of exactly "NONE" (nothing durable) becomes null.
function parseHandoff(raw) {
  const markers = [
    ['progress', /===\s*PROGRESS\s*===/i],
    ['claude', /===\s*CLAUDE\s*===/i],
    ['kickstart', /===\s*KICKSTART\s*===/i],
    ['end', /===\s*END\s*===/i],
  ];
  const found = [];
  for (const [key, re] of markers) { const m = raw.match(re); if (m) found.push({ key, start: m.index, after: m.index + m[0].length }); }
  found.sort((a, b) => a.start - b.start);
  const sec = {};
  for (let i = 0; i < found.length; i++) {
    const cur = found[i], next = found[i + 1];
    sec[cur.key] = raw.slice(cur.after, next ? next.start : raw.length).trim();
  }
  const progress = (sec.progress || '').trim();
  let claudeSection = (sec.claude || '').trim();
  if (!claudeSection || /^none[.!]?$/i.test(claudeSection)) claudeSection = null;
  const kickstart = (sec.kickstart || '').trim();
  return { progress, claudeSection, kickstart };
}

async function generateHandoff(meta) {
  const excerpt = await buildHandoffExcerpt(meta);
  if (!excerpt) {
    const err = new Error('This session has no conversation content to hand off.');
    err.code = 'EMPTY_TRANSCRIPT';
    throw err;
  }
  const dateStr = new Date().toISOString().slice(0, 10);
  const raw = await runClaude(handoffInstruction(dateStr), excerpt);
  const parsed = parseHandoff(raw);
  if (!parsed.progress) {
    const err = new Error('The model did not return a usable handoff. Try Regenerate.');
    err.code = 'PARSE_FAILED';
    throw err;
  }
  return {
    progress: parsed.progress,
    claudeSection: parsed.claudeSection,
    kickstart: parsed.kickstart,
    raw,
    generatedAt: new Date().toISOString(),
  };
}

// Fresh filesystem snapshot of the session's project dir (never trusts the client).
async function handoffFsInfo(meta) {
  const cwd = meta.cwd || null;
  let cwdExists = false, claudeMdExists = false, progressMdExists = false;
  if (cwd) {
    try { const st = await fsp.stat(cwd); cwdExists = st.isDirectory(); } catch (_) { cwdExists = false; }
    if (cwdExists) {
      try { await fsp.stat(path.join(cwd, 'CLAUDE.md')); claudeMdExists = true; } catch (_) {}
      try { await fsp.stat(path.join(cwd, 'PROGRESS.md')); progressMdExists = true; } catch (_) {}
    }
  }
  return { cwd, cwdExists, claudeMdExists, progressMdExists };
}

// Insert a new dated section into an existing PROGRESS.md: right after a leading
// "# " title line if there is one, else at the very top. Never deletes content.
function insertProgressSection(existing, section) {
  const sec = section.trim();
  const lines = existing.replace(/\r\n/g, '\n').split('\n');
  let idx = 0;
  while (idx < lines.length && lines[idx].trim() === '') idx++;
  const insertAt = (idx < lines.length && /^#\s+/.test(lines[idx])) ? idx + 1 : 0;
  const head = lines.slice(0, insertAt);
  const tail = lines.slice(insertAt);
  const merged = head.concat(['', ...sec.split('\n'), ''], tail);
  let out = merged.join('\n').replace(/\n{3,}/g, '\n\n');
  if (!out.endsWith('\n')) out += '\n';
  return out;
}

// Add or replace our fenced block inside an existing CLAUDE.md. If our markers are
// already present, replace only what's between them (idempotent); otherwise append.
function upsertClaudeBlock(existing, block) {
  const s = existing.indexOf(HANDOFF_CLAUDE_START);
  const e = existing.indexOf(HANDOFF_CLAUDE_END);
  if (s !== -1 && e !== -1 && e > s) {
    return existing.slice(0, s) + block + existing.slice(e + HANDOFF_CLAUDE_END.length);
  }
  let out = existing;
  if (!out.endsWith('\n')) out += '\n';
  out += '\n' + block + '\n';
  return out;
}

// Write PROGRESS.md (always) and CLAUDE.md (when asked) into the session's cwd.
// Target dir + filenames are entirely server-derived — the client supplies no path.
async function writeHandoff(meta, record, includeClaudeMd) {
  const cwd = meta.cwd;
  if (!cwd) {
    const e = new Error('This session has no recorded project directory, so files cannot be written.');
    e.code = 'CWD_MISSING';
    throw e;
  }
  let st;
  try { st = await fsp.stat(cwd); } catch (_) {
    const e = new Error("The session's project directory no longer exists: " + cwd);
    e.code = 'CWD_MISSING';
    throw e;
  }
  if (!st.isDirectory()) {
    const e = new Error("The session's project path is not a directory: " + cwd);
    e.code = 'CWD_MISSING';
    throw e;
  }

  const written = [];
  const project = projectDisplayName(meta);

  // --- PROGRESS.md (always) ---
  const progressPath = path.join(cwd, 'PROGRESS.md');
  const section = (record.progress || '').trim();
  let existing = null;
  try { existing = await fsp.readFile(progressPath, 'utf8'); } catch (_) { existing = null; }
  const progressContent = (existing == null)
    ? '# Progress — ' + project + '\n\n' + section + '\n'
    : insertProgressSection(existing, section);
  await fsp.writeFile(progressPath, progressContent);
  written.push(progressPath);

  // --- CLAUDE.md (opt-in, only when there's durable content) ---
  if (includeClaudeMd && record.claudeSection) {
    const claudePath = path.join(cwd, 'CLAUDE.md');
    const block = HANDOFF_CLAUDE_START + '\n' + record.claudeSection.trim() + '\n' + HANDOFF_CLAUDE_END;
    let cExisting = null;
    try { cExisting = await fsp.readFile(claudePath, 'utf8'); } catch (_) { cExisting = null; }
    const claudeContent = (cExisting == null) ? block + '\n' : upsertClaudeBlock(cExisting, block);
    await fsp.writeFile(claudePath, claudeContent);
    written.push(claudePath);
  }

  return written;
}

// ---------------------------------------------------------------------------
// Deep transcript search (scans user/assistant text, stream-read, capped)
// ---------------------------------------------------------------------------

const readline = require('readline');

async function deepSearch(q) {
  const needle = q.toLowerCase();
  const MAX_TOTAL = 200, MAX_PER = 8;
  const listing = (await listTranscripts()).sort((a, b) => b.mtimeMs - a.mtimeMs);
  const results = [];
  let truncated = false;

  for (const entry of listing) {
    if (results.length >= MAX_TOTAL) { truncated = true; break; }
    const cached = metaCache.get(entry.filePath);
    const meta = cached ? cached.meta : null;
    const title = meta ? displayTitle(meta) : entry.sessionId.slice(0, 8);
    const project = meta ? projectDisplayName(meta) : entry.projectKey;
    let perSession = 0;

    await new Promise((resolve) => {
      let done = false;
      const finish = () => { if (!done) { done = true; resolve(); } };
      const stream = fs.createReadStream(entry.filePath, { encoding: 'utf8' });
      stream.on('error', finish);
      const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
      rl.on('line', (line) => {
        if (perSession >= MAX_PER || results.length >= MAX_TOTAL) { rl.close(); return; }
        if (!line) return;
        if (line.indexOf('"isSidechain":true') !== -1) return;
        const isUser = line.indexOf('"type":"user"') !== -1;
        const isAssistant = line.indexOf('"type":"assistant"') !== -1;
        if (!isUser && !isAssistant) return;
        if (isUser && (line.indexOf('"isMeta":true') !== -1 || line.indexOf('"tool_result"') !== -1)) return;
        if (line.toLowerCase().indexOf(needle) === -1) return; // cheap prefilter before JSON.parse
        let obj; try { obj = JSON.parse(line); } catch (_) { return; }
        const text = isUser ? userText(obj) : assistantText(obj);
        if (!text) return;
        if (isUser && !isRealPrompt(text)) return;
        const mi = text.toLowerCase().indexOf(needle);
        if (mi === -1) return;
        const start = Math.max(0, mi - 120);
        const end = Math.min(text.length, mi + needle.length + 120);
        let snippet = text.slice(start, end).replace(/\s+/g, ' ').trim();
        snippet = (start > 0 ? '…' : '') + snippet + (end < text.length ? '…' : '');
        results.push({
          sessionId: entry.sessionId,
          sessionTitle: title,
          projectName: project,
          role: isUser ? 'user' : 'assistant',
          snippet,
          timestamp: typeof obj.timestamp === 'string' ? obj.timestamp : null,
        });
        perSession++;
        if (perSession >= MAX_PER || results.length >= MAX_TOTAL) rl.close();
      });
      rl.on('close', finish);
    });
  }
  if (results.length >= MAX_TOTAL) truncated = true;
  return { results, truncated };
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

    if (pathname === '/api/usage' && method === 'GET') {
      await scanSessions(); // ensure metaCache (and its usage records) are warm & fresh
      const fromRaw = parsed.searchParams.get('from');
      const toRaw = parsed.searchParams.get('to');
      const fromMs = fromRaw ? Date.parse(fromRaw) : NaN;
      const toMs = toRaw ? Date.parse(toRaw) : NaN;
      const fromDay = Number.isNaN(fromMs) ? null : localDayKey(fromMs);
      const toDay = Number.isNaN(toMs) ? null : localDayKey(toMs);
      return sendJson(res, 200, aggregateUsage(fromDay, toDay));
    }

    if (pathname === '/api/search' && method === 'GET') {
      const q = (parsed.searchParams.get('q') || '').trim();
      if (q.length < 3) return sendJson(res, 200, { query: q, results: [], truncated: false });
      await scanSessions(); // warm titles/projects for result grouping
      const { results, truncated } = await deepSearch(q);
      return sendJson(res, 200, { query: q, results, truncated });
    }

    const usageMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/usage$/);
    if (usageMatch && method === 'GET') {
      const meta = await getSessionMeta(usageMatch[1]);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      const u = (meta.usage && meta.usage.totals) || { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, activeSeconds: 0 };
      return sendJson(res, 200, {
        tokens: { input: u.input || 0, output: u.output || 0, cacheRead: u.cacheRead || 0, cacheWrite: u.cacheWrite || 0 },
        cost: u.cost || 0,
        activeSeconds: u.activeSeconds || 0,
        byModel: (meta.usage && meta.usage.byModelAll) || [],
      });
    }

    const briefMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/brief$/);
    if (briefMatch && (method === 'POST' || method === 'GET')) {
      const id = briefMatch[1];
      if (method === 'GET') {
        const b = briefs[id];
        if (!b) return sendJson(res, 404, { error: 'No brief yet' });
        return sendJson(res, 200, b);
      }
      const meta = await getSessionMeta(id);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      try {
        const brief = await generateBrief(meta);
        briefs[id] = Object.assign({}, brief, { sessionLastActivity: meta.lastActivityAt });
        saveBriefs();
        return sendJson(res, 200, briefs[id]);
      } catch (e) {
        console.error('[reprise] Brief failed:', e.message);
        return sendJson(res, 500, { error: e.message, code: e.code || 'ERROR' });
      }
    }

    // Write files into the session's project dir. Match BEFORE /handoff so the
    // trailing "/write" segment isn't misrouted.
    const handoffWriteMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/handoff\/write$/);
    if (handoffWriteMatch && method === 'POST') {
      const id = handoffWriteMatch[1];
      const meta = await getSessionMeta(id);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      const record = handoffs[id];
      if (!record) return sendJson(res, 400, { error: 'Generate a handoff first.', code: 'NO_HANDOFF' });
      let body = {};
      try { body = JSON.parse((await readBody(req)) || '{}'); } catch (_) { body = {}; }
      const includeClaudeMd = body.includeClaudeMd === true;
      try {
        const written = await writeHandoff(meta, record, includeClaudeMd);
        return sendJson(res, 200, { written });
      } catch (e) {
        console.error('[claude-sessions] Handoff write failed:', e.message);
        const status = (e.code === 'CWD_MISSING') ? 400 : 500;
        return sendJson(res, status, { error: e.message, code: e.code || 'ERROR' });
      }
    }

    const handoffMatch = pathname.match(/^\/api\/sessions\/([^/]+)\/handoff$/);
    if (handoffMatch && (method === 'POST' || method === 'GET')) {
      const id = handoffMatch[1];
      const meta = await getSessionMeta(id);
      if (!meta) return sendJson(res, 404, { error: 'Session not found' });
      if (method === 'GET') {
        const h = handoffs[id];
        if (!h) return sendJson(res, 404, { error: 'No handoff yet' });
        const fsInfo = await handoffFsInfo(meta);
        return sendJson(res, 200, Object.assign({}, h, fsInfo));
      }
      try {
        const handoff = await generateHandoff(meta);
        handoffs[id] = Object.assign({}, handoff, {
          sessionLastActivity: meta.lastActivityAt,
          cwd: meta.cwd,
          project: projectDisplayName(meta),
        });
        saveHandoffs();
        const fsInfo = await handoffFsInfo(meta);
        return sendJson(res, 200, Object.assign({}, handoffs[id], fsInfo));
      } catch (e) {
        console.error('[claude-sessions] Handoff failed:', e.message);
        return sendJson(res, 500, { error: e.message, code: e.code || 'ERROR' });
      }
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
  console.log('  Claude Code Session Indexer — Web');
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
