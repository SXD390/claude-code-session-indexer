// Test for the OPTIONAL SQLite FTS5 search backend (web/lib/index-sqlite.js).
//
// This test is DUAL-MODE and always exits 0 unless something is genuinely wrong:
//
//   * If node:sqlite is unavailable (e.g. CI on Node 20, or the module isn't
//     compiled with FTS5) it asserts the FALLBACK contract — isAvailable() is
//     false and the linear deepSearch still returns the expected hits — then
//     passes as a no-op. This is the path CI exercises.
//
//   * If node:sqlite IS available (local Node 22.5+), it builds a real FTS index
//     over a temp fixture and asserts that FTS search returns the SAME session
//     hits as the linear scan for a sample query, and that snippets are redacted.
//
// The index db is written to an isolated temp dir (CSI_INDEX_DIR) so a real
// user's index.db is never touched. Run:  node web/test/index.mjs
import { createRequire } from 'node:module';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));

const failures = [];
function check(cond, label) {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`);
  if (!cond) failures.push(label);
}

// --- Is the built-in node:sqlite (with FTS5) usable on this Node? ---
let sqlitePresent = false;
try {
  const { DatabaseSync } = require('node:sqlite');
  const probe = new DatabaseSync(':memory:');
  probe.exec('CREATE VIRTUAL TABLE t USING fts5(a);'); // also proves FTS5 is compiled in
  probe.close();
  sqlitePresent = true;
} catch (_) {
  sqlitePresent = false;
}
console.log(`node:sqlite + FTS5 available: ${sqlitePresent} (Node ${process.version})`);

// --- Build a deterministic fixture: two sessions, only one mentions the term ---
const SID_HIT = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const SID_MISS = '11111111-2222-3333-4444-555555555555';
const SECRET = 'sk-ant-api03-ABCDEFGHIJKLMNOP0123456789';
const TERM = 'photosynthesis';

const dataDir = mkdtempSync(path.join(tmpdir(), 'csi-index-data-'));
const indexDir = mkdtempSync(path.join(tmpdir(), 'csi-index-db-'));
const projKey = '-Users-demo-dev-plants';
const projDir = path.join(dataDir, 'projects', projKey);
mkdirSync(projDir, { recursive: true });

const cwd = '/Users/demo/dev/plants';
function line(o) { return JSON.stringify(o); }

// Session that SHOULD match — the ASSISTANT text is the only place the query
// term appears, and it sits right next to a secret so the reconstructed snippet
// must redact it. (The user turn deliberately omits the term.)
writeFileSync(path.join(projDir, `${SID_HIT}.jsonl`), [
  line({ type: 'user', message: { role: 'user', content: 'Explain how plants make energy from sunlight.' },
    uuid: 'u1', timestamp: '2026-06-25T10:00:00Z', cwd, gitBranch: 'main', version: '2.1.0', sessionId: SID_HIT }),
  line({ type: 'assistant', message: { id: 'm1', model: 'claude-sonnet-4-5',
    content: [{ type: 'text', text: `Great question about ${TERM}. Note the api key ${SECRET} in the config file.` }] },
    requestId: 'r1', uuid: 'a1', timestamp: '2026-06-25T10:00:30Z', cwd, sessionId: SID_HIT }),
].join('\n') + '\n');

// Session that should NOT match the term.
writeFileSync(path.join(projDir, `${SID_MISS}.jsonl`), [
  line({ type: 'user', message: { role: 'user', content: 'Refactor the widget cache please.' },
    uuid: 'u2', timestamp: '2026-06-25T11:00:00Z', cwd, gitBranch: 'main', version: '2.1.0', sessionId: SID_MISS }),
  line({ type: 'assistant', message: { id: 'm2', model: 'claude-sonnet-4-5',
    content: [{ type: 'text', text: 'Done — the widget cache now uses an LRU policy.' }] },
    requestId: 'r2', uuid: 'a2', timestamp: '2026-06-25T11:00:30Z', cwd, sessionId: SID_MISS }),
].join('\n') + '\n');

// Point the server at the fixture and isolate the index db BEFORE requiring it.
process.env.CSI_CLAUDE_DIR = dataDir;
process.env.CSI_INDEX_DIR = indexDir;
delete process.env.CSI_INDEX; // start on the default (index OFF) path

const S = require(path.join(here, '..', 'server.js'));
const IDX = require(path.join(here, '..', 'lib', 'index-sqlite.js'));

const idsOf = (r) => Array.from(new Set((r.results || []).map((x) => x.sessionId))).sort();

try {
  await S.scanSessions(); // warm metaCache (titles/projects) for both search paths

  // --- Fallback contract (this is the CI / Node 20 path, but true whenever the
  //     index is OFF): isAvailable() is false and linear search still works. ---
  check(IDX.isAvailable() === false, 'isAvailable() is false when CSI_INDEX is unset');
  const scan = await S.deepSearch(TERM);
  const scanIds = idsOf(scan);
  check(scanIds.includes(SID_HIT), 'linear scan finds the matching session');
  check(!scanIds.includes(SID_MISS), 'linear scan excludes the non-matching session');
  const scanHitSnippet = (scan.results.find((r) => r.sessionId === SID_HIT) || {}).snippet || '';
  check(scanHitSnippet.includes('[REDACTED]') && !scanHitSnippet.includes(SECRET),
    'linear scan snippet is redacted');

  if (!sqlitePresent) {
    console.log('\nnode:sqlite unavailable — FTS path skipped (fallback verified). This is expected on Node < 22.5.');
  } else {
    // --- FTS path: opt in, build the index, and prove parity with the scan. ---
    process.env.CSI_INDEX = '1';
    check(IDX.isAvailable() === true, 'isAvailable() is true when CSI_INDEX=1 and node:sqlite loads');

    const built = await IDX.ensureIndex();
    check(built && built.ok === true, 'ensureIndex() builds successfully');
    check(built.total >= 3, `index holds the fixture messages (indexed ${built.total})`);

    // deepSearch now routes through the FTS index (same call, same shape).
    const idx = await S.deepSearch(TERM);
    const idxIds = idsOf(idx);
    check(idxIds.includes(SID_HIT), 'FTS search finds the matching session');
    check(!idxIds.includes(SID_MISS), 'FTS search excludes the non-matching session');
    check(JSON.stringify(idxIds) === JSON.stringify(scanIds), 'FTS hits equal linear-scan hits for the sample query');

    const idxHit = idx.results.find((r) => r.sessionId === SID_HIT) || {};
    check(idxHit.snippet && idxHit.snippet.includes('[REDACTED]') && !idxHit.snippet.includes(SECRET),
      'FTS snippet is redacted');
    check(idxHit.projectName === 'plants', 'FTS result carries the project name');

    // Incremental re-run is cheap: nothing changed → zero re-indexed messages.
    const again = await IDX.ensureIndex();
    check(again.ok && again.indexed === 0 && again.changed === 0, 'ensureIndex() re-run is incremental (no changes)');
  }
} catch (e) {
  console.log(`FAIL  unexpected error: ${e && e.stack ? e.stack : e}`);
  failures.push('unexpected error');
} finally {
  try { rmSync(dataDir, { recursive: true, force: true }); } catch (_) {}
  try { rmSync(indexDir, { recursive: true, force: true }); } catch (_) {}
}

console.log(failures.length ? `\nWEB INDEX: ${failures.length} FAILURE(S)` : '\nWEB INDEX: ALL PASS');
process.exit(failures.length ? 1 : 0);
