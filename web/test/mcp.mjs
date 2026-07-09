// MCP stdio test for the Claude Code Session Indexer.
// Builds a tiny fake CSI_CLAUDE_DIR fixture (one project, one transcript), spawns
// web/mcp-server.js, and drives a real JSON-RPC handshake over stdin/stdout:
//   initialize → tools/list → tools/call (list_sessions, search_sessions, …).
// Asserts valid JSON-RPC framing + expected result shapes, and that stdout carries
// ONLY JSON-RPC (no stray logs). Exits non-zero on any failure so CI catches it.
//
// Run:  node web/test/mcp.mjs
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const MCP = path.join(here, '..', 'mcp-server.js');

const failures = [];
function check(cond, label) {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`);
  if (!cond) failures.push(label);
}

// --- Build a deterministic fixture: ~/.claude-shaped tree with one transcript ---
const SID = '11111111-2222-3333-4444-555555555555';
const dataDir = mkdtempSync(path.join(tmpdir(), 'csi-mcp-'));
const projKey = '-Users-demo-dev-widget-shop';
const projDir = path.join(dataDir, 'projects', projKey);
mkdirSync(projDir, { recursive: true });

const cwd = '/Users/demo/dev/widget-shop';
const lines = [
  { type: 'ai-title', aiTitle: 'Widget caching decision', sessionId: SID },
  {
    type: 'user',
    message: { role: 'user', content: "Let's implement the widget caching layer decision we discussed." },
    uuid: 'aaaa1111-0000-0000-0000-000000000001',
    timestamp: '2026-06-25T23:49:00Z',
    cwd, gitBranch: 'main', version: '2.1.0', sessionId: SID,
  },
  {
    type: 'assistant',
    message: {
      id: 'msg_1', model: 'claude-sonnet-4-5-20250101',
      content: [{ type: 'text', text: 'Agreed — I will build the caching layer with an LRU eviction policy.' }],
      usage: { input_tokens: 100, output_tokens: 200, cache_read_input_tokens: 50, cache_creation_input_tokens: 10 },
    },
    requestId: 'req_1', uuid: 'aaaa1111-0000-0000-0000-000000000002',
    timestamp: '2026-06-25T23:49:30Z', cwd, sessionId: SID,
  },
];
writeFileSync(path.join(projDir, `${SID}.jsonl`), lines.map((l) => JSON.stringify(l)).join('\n') + '\n');

// --- Minimal JSON-RPC-over-stdio client ---
const proc = spawn(process.execPath, [MCP], {
  env: { ...process.env, CSI_CLAUDE_DIR: dataDir },
  stdio: ['pipe', 'pipe', 'inherit'], // stderr → inherit so logs stay OFF stdout
});

const stdoutLines = [];         // every raw stdout line, for the "only JSON-RPC" check
const pending = new Map();       // id → resolve
let buffer = '';

proc.stdout.setEncoding('utf8');
proc.stdout.on('data', (chunk) => {
  buffer += chunk;
  let nl;
  while ((nl = buffer.indexOf('\n')) !== -1) {
    const line = buffer.slice(0, nl).replace(/\r$/, '');
    buffer = buffer.slice(nl + 1);
    if (!line.trim()) continue;
    stdoutLines.push(line);
    let msg;
    try { msg = JSON.parse(line); } catch { failures.push(`non-JSON on stdout: ${line.slice(0, 80)}`); continue; }
    if (msg.id !== undefined && msg.id !== null && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});

let nextId = 1;
function request(method, params) {
  const id = nextId++;
  const payload = { jsonrpc: '2.0', id, method };
  if (params !== undefined) payload.params = params;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout waiting for ${method}`)), 8000);
    pending.set(id, (msg) => { clearTimeout(timer); resolve(msg); });
    proc.stdin.write(JSON.stringify(payload) + '\n');
  });
}
function notify(method, params) {
  const payload = { jsonrpc: '2.0', method };
  if (params !== undefined) payload.params = params;
  proc.stdin.write(JSON.stringify(payload) + '\n');
}

// Parse a tools/call result's text content back into an object.
function toolJson(resp) {
  const c = resp && resp.result && resp.result.content;
  if (!Array.isArray(c) || !c[0] || c[0].type !== 'text') throw new Error('no text content');
  return JSON.parse(c[0].text);
}

try {
  // 1. initialize
  const init = await request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'mcp-test', version: '0' },
  });
  check(init.jsonrpc === '2.0' && init.id === 1, 'initialize is valid JSON-RPC (jsonrpc 2.0, id echoed)');
  check(init.result && init.result.protocolVersion === '2024-11-05', 'initialize returns protocolVersion 2024-11-05');
  check(!!(init.result && init.result.serverInfo && init.result.serverInfo.name), 'initialize returns serverInfo.name');
  check(!!(init.result && init.result.capabilities && init.result.capabilities.tools), 'initialize advertises tools capability');

  // notifications/initialized — no response expected
  notify('notifications/initialized');

  // ping
  const pong = await request('ping');
  check(pong.result && typeof pong.result === 'object', 'ping → empty result object');

  // 2. tools/list
  const list = await request('tools/list');
  const tools = list.result && list.result.tools;
  check(Array.isArray(tools) && tools.length === 6, `tools/list returns 6 tools (got ${tools && tools.length})`);
  const names = new Set((tools || []).map((t) => t.name));
  for (const n of ['list_sessions', 'search_sessions', 'get_session', 'get_project_journal', 'get_usage', 'get_resume_command']) {
    check(names.has(n), `tools/list includes ${n}`);
  }
  check((tools || []).every((t) => t.description && t.inputSchema && t.inputSchema.type === 'object'),
    'every tool has a description + object inputSchema');

  // 3a. tools/call — list_sessions
  const ls = await request('tools/call', { name: 'list_sessions', arguments: {} });
  const lsData = toolJson(ls);
  check(Array.isArray(lsData.sessions) && lsData.sessions.length === 1, `list_sessions returns the 1 fixture session (got ${lsData.sessions && lsData.sessions.length})`);
  const sess = lsData.sessions[0];
  check(sess && sess.id === SID, 'list_sessions session id matches fixture UUID');
  check(sess && sess.title === 'Widget caching decision', 'list_sessions surfaces the AI title');
  check(sess && sess.prompts === 1, 'list_sessions counts 1 user prompt');
  check(sess && typeof sess.resumeCommand === 'string' && sess.resumeCommand.includes(`claude --resume ${SID}`),
    'list_sessions includes a resume command string');

  // list_sessions with a project filter that misses → empty
  const lsMiss = toolJson(await request('tools/call', { name: 'list_sessions', arguments: { project: 'no-such-project' } }));
  check(lsMiss.sessions.length === 0, 'list_sessions project filter excludes non-matches');

  // 3b. tools/call — search_sessions
  const sr = await request('tools/call', { name: 'search_sessions', arguments: { query: 'caching' } });
  const srData = toolJson(sr);
  check(Array.isArray(srData.results) && srData.results.length >= 1, `search_sessions finds "caching" (got ${srData.results && srData.results.length})`);
  const hit = (srData.results || [])[0];
  check(hit && hit.sessionId === SID, 'search hit carries the session id');
  check(hit && typeof hit.snippet === 'string' && hit.snippet.toLowerCase().includes('caching'), 'search snippet contains the query');
  check(hit && (hit.role === 'user' || hit.role === 'assistant'), 'search hit has a role');

  // search too-short query → tool error
  const srShort = await request('tools/call', { name: 'search_sessions', arguments: { query: 'ab' } });
  check(srShort.result && srShort.result.isError === true, 'search_sessions rejects <3 char query (isError)');

  // 3c. get_session
  const gs = toolJson(await request('tools/call', { name: 'get_session', arguments: { sessionId: SID } }));
  check(gs.sessionId === SID && gs.cwd === cwd, 'get_session returns metadata for the fixture');
  check(gs.preview && Array.isArray(gs.preview.messages) && gs.preview.messages.length >= 2, 'get_session returns a conversation preview (>=2 msgs)');

  // get_session invalid UUID → tool error
  const gsBad = await request('tools/call', { name: 'get_session', arguments: { sessionId: 'not-a-uuid' } });
  check(gsBad.result && gsBad.result.isError === true, 'get_session rejects non-UUID id (isError)');

  // 3d. get_project_journal (oldest-first)
  const gj = toolJson(await request('tools/call', { name: 'get_project_journal', arguments: { project: 'widget-shop' } }));
  check(Array.isArray(gj.entries) && gj.entries.length === 1, 'get_project_journal lists the project session');
  check(gj.entries[0] && gj.entries[0].sessionId === SID && typeof gj.entries[0].cost === 'number', 'journal entry has session id + numeric cost');

  // 3e. get_usage
  const gu = toolJson(await request('tools/call', { name: 'get_usage', arguments: {} }));
  check(gu.totals && gu.totals.tokens && typeof gu.totals.cost === 'number', 'get_usage returns totals with cost + tokens');
  check(Array.isArray(gu.byModel) && Array.isArray(gu.byProject), 'get_usage returns byModel + byProject arrays');
  check(typeof gu.costBasis === 'string' && /API-equivalent/i.test(gu.costBasis), 'get_usage labels cost as API-equivalent');

  // 3f. get_resume_command
  const grc = toolJson(await request('tools/call', { name: 'get_resume_command', arguments: { sessionId: SID } }));
  check(typeof grc.resumeCommand === 'string' && grc.resumeCommand.includes(`claude --resume ${SID}`), 'get_resume_command returns the exact resume string');

  // unknown tool → isError
  const unk = await request('tools/call', { name: 'does_not_exist', arguments: {} });
  check(unk.result && unk.result.isError === true, 'unknown tool → isError result');

  // unknown method → JSON-RPC error -32601
  const bad = await request('nonexistent/method');
  check(bad.error && bad.error.code === -32601, 'unknown method → JSON-RPC -32601');

  // 4. stdout carried ONLY JSON-RPC (every collected line is valid jsonrpc 2.0)
  const allJsonRpc = stdoutLines.every((l) => {
    try { const o = JSON.parse(l); return o.jsonrpc === '2.0'; } catch { return false; }
  });
  check(allJsonRpc && stdoutLines.length > 0, `stdout carried ONLY JSON-RPC (${stdoutLines.length} lines)`);
} catch (err) {
  console.error('mcp test error:', err && err.stack ? err.stack : err);
  failures.push('harness: ' + (err && err.message));
} finally {
  proc.stdin.end();
  proc.kill('SIGKILL');
}

console.log(failures.length ? `\nWEB MCP: ${failures.length} FAILURE(S)` : '\nWEB MCP: ALL PASS');
process.exit(failures.length ? 1 : 0);
