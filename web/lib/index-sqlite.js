'use strict';

/*
 * Optional SQLite FTS5 full-text-search backend — OPT-IN, ZERO npm deps.
 * ---------------------------------------------------------------------------
 * The Session Indexer's default deep-search reads every transcript file on each
 * query (see server.js `deepSearch`/`linearDeepSearch`). That is fine for most
 * people, but power users with thousands of long sessions can make it near-
 * instant by building a persistent full-text index. This module is that index.
 *
 * IT IS STRICTLY ADDITIVE AND OFF BY DEFAULT. Nothing here runs, and no database
 * file is created or touched, unless the user explicitly opts in with the env
 * var CSI_INDEX=1 (or the `--index` CLI flag). With it unset, the app behaves
 * byte-for-byte as before.
 *
 * REQUIREMENTS / ZERO DEPENDENCIES:
 *   - Uses ONLY Node's BUILT-IN `node:sqlite` module. No npm packages, ever
 *     (no better-sqlite3, no sqlite3). package.json stays "dependencies": {}.
 *   - `node:sqlite` is experimental and only ships on Node 22.5+ (and needs FTS5
 *     compiled in). On Node 18/20 — including CI — `require('node:sqlite')`
 *     throws; we catch it and `isAvailable()` returns false, so callers fall back
 *     silently to the existing linear scan. Any SQLite error at build/search time
 *     also degrades to the linear scan. The app works identically with no index.
 *
 * PRIVACY: indexed text is REDACTED before it is stored (we index the output of
 * server.js's `extractPreview`, which scrubs secrets exactly like the live
 * preview / search paths). Search snippets are therefore redacted the same way
 * linear search redacts them.
 *
 * INTEGRATION: server.js injects the few helpers it owns via `configure()` so
 * this module never has to `require('../server.js')` back (no circular load).
 * The index db lives at <app-data>/index.db (override dir with CSI_INDEX_DIR,
 * mirroring CSI_CLAUDE_DIR — used only by tests/demos).
 */

const path = require('path');
const fs = require('fs');

// Lazily-loaded node:sqlite handle + memoized availability of the module itself.
let sqlite = null;
let sqliteLoadTried = false;
let sqliteLoadOk = false;

// Injected by server.js configure(): the read-only helpers this index reuses.
let deps = null;

let db = null;          // open DatabaseSync handle (created on first use)
let dbReady = false;    // an index build has completed successfully at least once
let dbBroken = false;   // a structural SQLite error occurred → give up, use scan

// Per-transcript extraction caps: index the FULL redacted message text.
const EXTRACT_MSG_LIMIT = 1000000;
const EXTRACT_TEXT_CAP = 1000000;

// Result caps — mirror server.js `deepSearch` so the switch is invisible.
const MAX_TOTAL = 200;
const MAX_PER = 8;
const SNIPPET_PAD = 120;

// --- Opt-in gate: CSI_INDEX=1 (or --index). Checked live so tests can toggle. ---
function envEnabled() {
  const v = process.env.CSI_INDEX;
  if (v === '1' || v === 'true' || v === 'yes') return true;
  if (process.argv.includes('--index')) return true;
  return false;
}

// Try to load the built-in node:sqlite module exactly once. Absent on Node <22.5.
function loadSqlite() {
  if (sqliteLoadTried) return sqliteLoadOk;
  sqliteLoadTried = true;
  try {
    // eslint-disable-next-line global-require
    const mod = require('node:sqlite');
    sqliteLoadOk = !!(mod && mod.DatabaseSync);
    if (sqliteLoadOk) sqlite = mod;
  } catch (_) {
    sqliteLoadOk = false;
  }
  return sqliteLoadOk;
}

// TRUE only when the user opted in AND node:sqlite is loadable AND we haven't
// already hit a fatal SQLite error. Callers use this to decide index vs scan.
function isAvailable() {
  if (dbBroken) return false;
  if (!envEnabled()) return false;
  return loadSqlite();
}

// server.js hands us the helpers it owns so we never require() it back.
function configure(d) {
  deps = d || {};
}

function markBroken(e) {
  dbBroken = true;
  dbReady = false;
  try { console.error('[claude-sessions] FTS index disabled (SQLite error):', e && e.message ? e.message : e); } catch (_) {}
  try { if (db) db.close(); } catch (_) {}
  db = null;
}

function indexDir() {
  // CSI_INDEX_DIR overrides the location (tests/demos), mirroring CSI_CLAUDE_DIR.
  return process.env.CSI_INDEX_DIR || (deps && deps.appDataDir) || process.cwd();
}

function openDb() {
  if (db) return db;
  const dir = indexDir();
  fs.mkdirSync(dir, { recursive: true });
  const dbPath = path.join(dir, 'index.db');
  const handle = new sqlite.DatabaseSync(dbPath);
  handle.exec('PRAGMA journal_mode = WAL;');
  handle.exec('PRAGMA synchronous = NORMAL;');
  // FTS5 virtual table: only `text` is tokenized/searchable; the rest are stored
  // columns we read back to shape a result identical to deepSearch.
  handle.exec(
    'CREATE VIRTUAL TABLE IF NOT EXISTS messages USING fts5(' +
    'session_id UNINDEXED, project UNINDEXED, role UNINDEXED, text, ts UNINDEXED);'
  );
  // File-fingerprint table so re-runs only re-index CHANGED transcripts.
  handle.exec(
    'CREATE TABLE IF NOT EXISTS files (' +
    'path TEXT PRIMARY KEY, mtimeMs REAL, size INTEGER, session_id TEXT);'
  );
  db = handle;
  return db;
}

function metaFor(filePath) {
  try {
    const c = deps && deps.metaCache && deps.metaCache.get(filePath);
    return c ? c.meta : null;
  } catch (_) { return null; }
}

function metaForSession(sessionId) {
  try {
    const fp = deps && deps.sessionIndex && deps.sessionIndex.get(sessionId);
    return fp ? metaFor(fp) : null;
  } catch (_) { return null; }
}

// Build/refresh the FTS index incrementally. `sessions` may be the listing that
// server.js's listTranscripts() produces ({filePath, projectKey, sessionId,
// mtimeMs, size}); if omitted we fetch it ourselves. Only changed/new/removed
// transcripts touch the db. Returns {ok, indexed, changed, total, sessions}.
async function ensureIndex(sessions) {
  if (!isAvailable()) return { ok: false, indexed: 0, changed: 0, total: 0, sessions: 0 };

  let listing;
  if (Array.isArray(sessions) && sessions.length && sessions[0] && sessions[0].filePath) {
    listing = sessions;
  } else {
    try { listing = await deps.listTranscripts(); } catch (_) { listing = []; }
  }

  let d;
  try {
    d = openDb();
  } catch (e) {
    markBroken(e);
    return { ok: false, indexed: 0, changed: 0, total: 0, sessions: 0 };
  }

  try {
    const livePaths = new Set(listing.map((e) => e.filePath));
    const existing = d.prepare('SELECT path, session_id FROM files').all();

    // Which transcripts are new or changed since we last indexed them?
    const changed = [];
    const lookup = d.prepare('SELECT mtimeMs, size FROM files WHERE path = ?');
    for (const entry of listing) {
      const row = lookup.get(entry.filePath);
      if (row && row.mtimeMs === entry.mtimeMs && row.size === entry.size) continue;
      changed.push(entry);
    }

    // Extract redacted messages for changed files BEFORE opening the write
    // transaction (extractPreview is async; SQLite here is synchronous).
    const extracted = [];
    for (const entry of changed) {
      let msgs = [];
      try { msgs = await deps.extractPreview(entry.filePath, EXTRACT_MSG_LIMIT, EXTRACT_TEXT_CAP); } catch (_) { msgs = []; }
      const meta = metaFor(entry.filePath);
      const project = meta && deps.projectDisplayName ? deps.projectDisplayName(meta) : (entry.projectKey || '');
      extracted.push({ entry, msgs, project });
    }

    let indexed = 0;
    d.exec('BEGIN');
    try {
      const del = d.prepare('DELETE FROM messages WHERE session_id = ?');
      const delFile = d.prepare('DELETE FROM files WHERE path = ?');
      const ins = d.prepare('INSERT INTO messages(session_id, project, role, text, ts) VALUES (?, ?, ?, ?, ?)');
      const upFile = d.prepare(
        'INSERT INTO files(path, mtimeMs, size, session_id) VALUES (?, ?, ?, ?) ' +
        'ON CONFLICT(path) DO UPDATE SET mtimeMs = excluded.mtimeMs, size = excluded.size, session_id = excluded.session_id'
      );

      // Drop transcripts that no longer exist on disk.
      for (const row of existing) {
        if (!livePaths.has(row.path)) {
          if (row.session_id) del.run(row.session_id);
          delFile.run(row.path);
        }
      }

      // Re-index changed transcripts (delete this session's rows, reinsert).
      for (const { entry, msgs, project } of extracted) {
        del.run(entry.sessionId);
        for (const m of msgs) {
          if (!m || !m.text) continue;
          ins.run(entry.sessionId, project || '', m.role || '', m.text, m.timestamp || '');
          indexed++;
        }
        upFile.run(entry.filePath, entry.mtimeMs, entry.size, entry.sessionId);
      }

      d.exec('COMMIT');
    } catch (e) {
      try { d.exec('ROLLBACK'); } catch (_) {}
      throw e;
    }

    dbReady = true;
    const total = Number(d.prepare('SELECT COUNT(*) AS c FROM messages').get().c) || 0;
    const sessCount = Number(d.prepare('SELECT COUNT(*) AS c FROM files').get().c) || 0;
    return { ok: true, indexed, changed: changed.length, total, sessions: sessCount, path: path.join(indexDir(), 'index.db') };
  } catch (e) {
    markBroken(e);
    return { ok: false, indexed: 0, changed: 0, total: 0, sessions: 0 };
  }
}

// Wrap each whitespace-delimited term in double quotes so FTS5 treats hyphens,
// dots, colons etc. in code as literal phrase content instead of MATCH operators.
function buildMatch(query) {
  const terms = String(query || '').trim().split(/\s+/).filter(Boolean);
  if (!terms.length) return null;
  return terms.map((t) => '"' + t.replace(/"/g, '""') + '"').join(' ');
}

// Reconstruct a deepSearch-shaped ±120-char snippet from the (already redacted)
// stored text. Positioned on the query substring when present, else the head.
function makeSnippet(text, needle) {
  const t = text || '';
  const mi = needle ? t.toLowerCase().indexOf(needle) : -1;
  let start, end;
  if (mi === -1) {
    start = 0;
    end = Math.min(t.length, SNIPPET_PAD * 2);
  } else {
    start = Math.max(0, mi - SNIPPET_PAD);
    end = Math.min(t.length, mi + needle.length + SNIPPET_PAD);
  }
  let snippet = t.slice(start, end).replace(/\s+/g, ' ').trim();
  snippet = (start > 0 ? '…' : '') + snippet + (end < t.length ? '…' : '');
  return snippet; // stored text is already redacted, so the snippet is too
}

// Run an FTS5 MATCH query and return { results, truncated } in the EXACT shape of
// deepSearch. Returns null to signal "index not usable — caller should fall back
// to the linear scan" (not available, not yet built, or a SQLite error).
function search(query, limit) {
  if (!isAvailable() || !dbReady) return null;
  const match = buildMatch(query);
  if (!match) return { results: [], truncated: false };
  const cap = Math.min(limit || MAX_TOTAL, MAX_TOTAL);
  try {
    const d = openDb();
    // Pull a generous candidate set, then apply the same per-session cap as scan.
    const rows = d.prepare(
      'SELECT session_id, project, role, text, ts FROM messages WHERE messages MATCH ? LIMIT 5000'
    ).all(match);

    const needle = String(query || '').toLowerCase();
    const perSession = new Map();
    const results = [];
    let truncated = false;

    for (const row of rows) {
      if (results.length >= cap) { truncated = true; break; }
      const sid = row.session_id;
      const used = perSession.get(sid) || 0;
      if (used >= MAX_PER) continue;
      perSession.set(sid, used + 1);

      const meta = metaForSession(sid);
      const title = meta && deps.displayTitle ? deps.displayTitle(meta) : String(sid).slice(0, 8);
      const project = meta && deps.projectDisplayName ? deps.projectDisplayName(meta) : (row.project || '');

      results.push({
        sessionId: sid,
        sessionTitle: title,
        projectName: project,
        role: row.role || '',
        snippet: makeSnippet(row.text, needle),
        timestamp: row.ts || null,
      });
    }
    return { results, truncated };
  } catch (e) {
    // A query-time error degrades this ONE query to the linear scan; we don't
    // permanently disable the index for a benign hiccup.
    try { console.error('[claude-sessions] FTS query failed, falling back to scan:', e && e.message ? e.message : e); } catch (_) {}
    return null;
  }
}

module.exports = { isAvailable, configure, ensureIndex, search };
