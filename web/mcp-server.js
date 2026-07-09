#!/usr/bin/env node
'use strict';

/*
 * Claude Code Session Indexer — MCP server
 * ----------------------------------------
 * A zero-dependency Model Context Protocol server that lets Claude Code (or any
 * MCP client) query the user's LOCAL Claude Code session history over stdio:
 * "what did I decide last week in this repo?".
 *
 * TRANSPORT: MCP stdio. JSON-RPC 2.0 messages, one JSON object per line
 * (newline-delimited JSON — the framing every mainstream stdio MCP server uses).
 * We read stdin line by line, parse each line as a JSON-RPC message, and write
 * each response as a single line of JSON to stdout.
 *
 * INVARIANT: stdout is the protocol channel and carries ONLY JSON-RPC. All logs
 * go to stderr. Because server.js logs progress with console.log (→ stdout), we
 * reroute console.log to stderr BEFORE requiring it, so no stray text can ever
 * corrupt the framing.
 *
 * SAFETY: every tool here is READ-ONLY. No file writes, no process spawns, no
 * `claude --resume` execution. get_resume_command returns the command STRING for
 * the human/agent to run themselves; it never runs it. All returned text is
 * redacted for secrets (extractPreview / deepSearch scrub before returning).
 *
 * CSI_CLAUDE_DIR is honored transparently: server.js reads it at load time to
 * point at an alternate data root (used by demos and tests).
 */

// --- Guard the protocol channel: route console.log to stderr, keep stderr as-is.
// Must run before require('./server.js') so nothing it prints reaches stdout.
const _stderr = console.error.bind(console);
console.log = (...args) => _stderr(...args);
console.info = (...args) => _stderr(...args);
console.warn = (...args) => _stderr(...args);

const path = require('path');
const S = require(path.join(__dirname, 'server.js'));

const SERVER_NAME = 'claude-code-session-indexer';
const SERVER_VERSION = '1.0.0';
const PROTOCOL_VERSION = '2024-11-05';

const UUID_RE = S.UUID_RE;

// --- Result-size caps (defense against runaway payloads) ---
const LIST_LIMIT_DEFAULT = 50;
const LIST_LIMIT_MAX = 200;
const SEARCH_LIMIT_DEFAULT = 20;
const SEARCH_LIMIT_MAX = 100;
const PREVIEW_MESSAGES_MAX = 60; // capped conversation messages in get_session
const PREVIEW_TEXT_CAP = 1500;   // per-message char cap (matches the web preview)
const JOURNAL_LIMIT = 300;       // sessions per project journal

function log(...args) { _stderr('[csi-mcp]', ...args); }

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function clampInt(v, def, min, max) {
  const n = Number.isFinite(v) ? Math.floor(v) : parseInt(v, 10);
  if (!Number.isFinite(n)) return def;
  return Math.max(min, Math.min(max, n));
}

// Case-insensitive match of a project filter against a session's name/key/cwd.
function projectMatches(session, needle) {
  if (!needle) return true;
  const n = needle.toLowerCase();
  const fields = [session.projectName, session.projectKey, session.cwd];
  return fields.some((f) => typeof f === 'string' && f.toLowerCase().indexOf(n) !== -1);
}

function isNamed(session) {
  return !!((session.customTitle && session.customTitle.length) ||
            (session.aiTitle && session.aiTitle.length));
}

// Trim a full session record down to the compact list shape the tools return.
function listShape(session) {
  return {
    id: session.sessionId,
    title: session.title,
    project: session.projectName,
    cwd: session.cwd,
    lastActivity: session.lastActivityAt,
    createdAt: session.createdAt,
    prompts: session.userMessageCount,
    running: session.running,
    resumeCommand: session.resumeCommand,
  };
}

// ---------------------------------------------------------------------------
// Tool definitions (name → { schema, handler })
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: 'list_sessions',
    description:
      'List local Claude Code sessions with metadata (newest first). Optionally ' +
      'filter by project (matches project name, folder key, or cwd — case-insensitive ' +
      'substring), by named-only (has a custom or AI-assigned title), or by currently ' +
      'running. Returns id, title, project, cwd, lastActivity, prompt count, running ' +
      'flag, and the exact resume command string. Read-only.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Filter by project name / folder / cwd (case-insensitive substring).' },
        named: { type: 'boolean', description: 'If true, only sessions that have a custom or AI title.' },
        running: { type: 'boolean', description: 'If true, only sessions whose CLI process is still alive.' },
        limit: { type: 'number', description: `Max sessions to return (default ${LIST_LIMIT_DEFAULT}, max ${LIST_LIMIT_MAX}).` },
      },
      additionalProperties: false,
    },
    handler: async (args) => {
      const { sessions } = await S.scanSessions();
      const limit = clampInt(args.limit, LIST_LIMIT_DEFAULT, 1, LIST_LIMIT_MAX);
      let filtered = sessions;
      if (args.project) filtered = filtered.filter((s) => projectMatches(s, args.project));
      if (args.named === true) filtered = filtered.filter(isNamed);
      if (args.running === true) filtered = filtered.filter((s) => s.running === true);
      const total = filtered.length;
      const out = filtered.slice(0, limit).map(listShape);
      return { count: out.length, total, truncated: total > out.length, sessions: out };
    },
  },
  {
    name: 'search_sessions',
    description:
      'Full-text search across ALL local session transcripts (user + assistant ' +
      'messages, sidechains excluded). Returns matching snippets with the session id, ' +
      'title, project, role, and timestamp. Snippets are redacted for secrets. Great ' +
      'for "when did I discuss X" / "what did I decide about Y". Minimum query length 3.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search text (minimum 3 characters).' },
        limit: { type: 'number', description: `Max snippets to return (default ${SEARCH_LIMIT_DEFAULT}, max ${SEARCH_LIMIT_MAX}).` },
      },
      required: ['query'],
      additionalProperties: false,
    },
    handler: async (args) => {
      const q = typeof args.query === 'string' ? args.query.trim() : '';
      if (q.length < 3) return toolError('query must be at least 3 characters');
      const limit = clampInt(args.limit, SEARCH_LIMIT_DEFAULT, 1, SEARCH_LIMIT_MAX);
      await S.scanSessions(); // warm titles/projects for result grouping
      const { results, truncated } = await S.deepSearch(q);
      const out = results.slice(0, limit).map((r) => ({
        sessionId: r.sessionId,
        title: r.sessionTitle,
        project: r.projectName,
        role: r.role,
        snippet: r.snippet,
        timestamp: r.timestamp,
      }));
      return { query: q, count: out.length, truncated: truncated || results.length > out.length, results: out };
    },
  },
  {
    name: 'get_session',
    description:
      'Get one session by UUID: full metadata plus a capped, redacted preview of the ' +
      'conversation (user + assistant turns, oldest first). Use this to read what ' +
      'actually happened in a specific session found via list_sessions or ' +
      'search_sessions. Read-only.',
    inputSchema: {
      type: 'object',
      properties: {
        sessionId: { type: 'string', description: 'Session UUID (e.g. from list_sessions / search_sessions).' },
      },
      required: ['sessionId'],
      additionalProperties: false,
    },
    handler: async (args) => {
      const id = String(args.sessionId || '');
      if (!UUID_RE.test(id)) return toolError('invalid sessionId (must be a UUID)');
      const meta = await S.getSessionMeta(id);
      if (!meta) return toolError(`session not found: ${id}`);
      const messages = await S.extractPreview(meta.transcriptPath, PREVIEW_MESSAGES_MAX, PREVIEW_TEXT_CAP);
      const ut = (meta.usage && meta.usage.totals) || null;
      return {
        sessionId: meta.sessionId,
        title: S.displayTitle(meta),
        project: S.projectDisplayName(meta),
        projectKey: meta.projectKey,
        cwd: meta.cwd,
        gitBranch: meta.gitBranch,
        model: meta.model,
        createdAt: meta.createdAt,
        lastActivityAt: meta.lastActivityAt,
        prompts: meta.userMessageCount,
        assistantMessages: meta.assistantMessageCount,
        usage: ut
          ? { cost: ut.cost, activeSeconds: ut.activeSeconds,
              tokens: { input: ut.input, output: ut.output, cacheRead: ut.cacheRead, cacheWrite: ut.cacheWrite } }
          : null,
        resumeCommand: S.resumeCommandFor(meta),
        preview: { messageCount: messages.length, capped: messages.length >= PREVIEW_MESSAGES_MAX, messages },
      };
    },
  },
  {
    name: 'get_project_journal',
    description:
      'Chronological journal (OLDEST first) of every session in one project — a ' +
      'timeline of "what happened in this repo over time". Each entry has the session ' +
      'id, title, start date, last activity, active duration (seconds), prompt count, ' +
      'API-equivalent cost, and a cached AI summary if one exists. Read-only.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Project name / folder / cwd to match (case-insensitive substring).' },
      },
      required: ['project'],
      additionalProperties: false,
    },
    handler: async (args) => {
      const project = typeof args.project === 'string' ? args.project.trim() : '';
      if (!project) return toolError('project is required');
      const { sessions } = await S.scanSessions();
      const matched = sessions.filter((s) => projectMatches(s, project));
      // Oldest-first: prefer createdAt, fall back to lastActivityAt.
      const sortKey = (s) => Date.parse(s.createdAt || s.lastActivityAt || '') || 0;
      matched.sort((a, b) => sortKey(a) - sortKey(b));
      const entries = matched.slice(0, JOURNAL_LIMIT).map((s) => ({
        sessionId: s.sessionId,
        title: s.title,
        date: s.createdAt || s.lastActivityAt,
        lastActivity: s.lastActivityAt,
        durationSeconds: s.usage ? Math.round(s.usage.activeSeconds || 0) : 0,
        prompts: s.userMessageCount,
        cost: s.usage ? s.usage.cost : 0,
        summary: s.summary ? s.summary.text : null,
        resumeCommand: s.resumeCommand,
      }));
      // Distinct project display names among matches (helps disambiguate loose filters).
      const projects = Array.from(new Set(matched.map((s) => s.projectName)));
      return {
        project,
        matchedProjects: projects,
        count: entries.length,
        costNote: 'cost is API-equivalent (list price), not what a Claude subscription charges',
        entries,
      };
    },
  },
  {
    name: 'get_usage',
    description:
      'Usage / cost summary across all sessions for an optional ISO date range ' +
      '(inclusive, local day). Returns totals (active time, cost, tokens), a by-model ' +
      'breakdown, and a by-project breakdown. Costs are API-EQUIVALENT (list price), ' +
      'not what a Claude Pro/Max subscription actually bills. Read-only.',
    inputSchema: {
      type: 'object',
      properties: {
        fromISO: { type: 'string', description: 'Range start, ISO date/datetime (inclusive). Omit for open-ended.' },
        toISO: { type: 'string', description: 'Range end, ISO date/datetime (inclusive). Omit for open-ended.' },
      },
      additionalProperties: false,
    },
    handler: async (args) => {
      await S.scanSessions(); // warm the usage records
      const agg = S.usageForRange(args.fromISO || null, args.toISO || null);
      return {
        range: { fromISO: args.fromISO || null, toISO: args.toISO || null },
        costBasis: 'API-equivalent (list price); not subscription billing',
        totals: agg.totals,
        byModel: agg.byModel,
        byProject: agg.byProject,
      };
    },
  },
  {
    name: 'get_resume_command',
    description:
      'Return the EXACT shell command to resume a session in Claude Code, e.g. ' +
      '`cd "…" && claude --resume <id>`. This does NOT execute anything — it just ' +
      'returns the string for you or the user to run. Read-only.',
    inputSchema: {
      type: 'object',
      properties: {
        sessionId: { type: 'string', description: 'Session UUID to resume.' },
      },
      required: ['sessionId'],
      additionalProperties: false,
    },
    handler: async (args) => {
      const id = String(args.sessionId || '');
      if (!UUID_RE.test(id)) return toolError('invalid sessionId (must be a UUID)');
      const meta = await S.getSessionMeta(id);
      if (!meta) return toolError(`session not found: ${id}`);
      return {
        sessionId: meta.sessionId,
        cwd: meta.cwd,
        resumeCommand: S.resumeCommandFor(meta),
        note: 'command is not executed by this tool; run it yourself to resume',
      };
    },
  },
];

const TOOL_MAP = new Map(TOOLS.map((t) => [t.name, t]));

// A tool-domain error (bad args, not found) — surfaced as an isError tool result
// so the model sees the message, rather than a JSON-RPC protocol error.
function toolError(message) {
  const e = new Error(message);
  e.isToolError = true;
  throw e;
}

// ---------------------------------------------------------------------------
// JSON-RPC plumbing (newline-delimited JSON over stdio)
// ---------------------------------------------------------------------------

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function sendResult(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function sendError(id, code, message, data) {
  const error = { code, message };
  if (data !== undefined) error.data = data;
  send({ jsonrpc: '2.0', id, error });
}

async function handleToolsCall(id, params) {
  const name = params && params.name;
  const args = (params && params.arguments) || {};
  const tool = TOOL_MAP.get(name);
  if (!tool) {
    // Unknown tool: report as a tool-call error result so the client can recover.
    return sendResult(id, {
      isError: true,
      content: [{ type: 'text', text: `Unknown tool: ${name}` }],
    });
  }
  try {
    const result = await tool.handler(args);
    sendResult(id, {
      content: [{ type: 'text', text: JSON.stringify(result) }],
    });
  } catch (err) {
    if (err && err.isToolError) {
      sendResult(id, { isError: true, content: [{ type: 'text', text: `Error: ${err.message}` }] });
    } else {
      log('tool handler crashed:', name, err && err.stack ? err.stack : err);
      sendResult(id, { isError: true, content: [{ type: 'text', text: `Internal error running ${name}: ${err && err.message}` }] });
    }
  }
}

async function dispatch(msg) {
  const { id, method, params } = msg;
  const isNotification = id === undefined || id === null;

  switch (method) {
    case 'initialize':
      return sendResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
        capabilities: { tools: {} },
      });

    case 'notifications/initialized':
    case 'initialized':
      return; // notification — no response

    case 'ping':
      if (!isNotification) sendResult(id, {});
      return;

    case 'tools/list':
      return sendResult(id, {
        tools: TOOLS.map((t) => ({ name: t.name, description: t.description, inputSchema: t.inputSchema })),
      });

    case 'tools/call':
      return handleToolsCall(id, params);

    default:
      // Ignore unknown notifications; error on unknown requests.
      if (isNotification) return;
      return sendError(id, -32601, `Method not found: ${method}`);
  }
}

// ---------------------------------------------------------------------------
// stdin reader: buffer bytes, split on newlines, dispatch each JSON message
// ---------------------------------------------------------------------------

function start() {
  log(`starting — protocol ${PROTOCOL_VERSION}, data root: ${S.CLAUDE_ROOT}`);
  let buffer = '';
  // Track in-flight request handling so that if stdin closes (a client that pipes
  // input and disconnects, or a test), we drain pending async work before exiting
  // instead of dropping responses mid-flight.
  const inflight = new Set();
  process.stdin.setEncoding('utf8');

  function processLine(raw) {
    const line = raw.replace(/\r$/, '').trim();
    if (!line) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch (_) {
      // Parse error: id unknown, respond with null id per JSON-RPC.
      sendError(null, -32700, 'Parse error');
      return;
    }
    // Dispatch; guard so one bad message can't take the loop down.
    const p = Promise.resolve()
      .then(() => dispatch(msg))
      .catch((err) => {
        log('dispatch error:', err && err.stack ? err.stack : err);
        if (msg && msg.id !== undefined && msg.id !== null) {
          sendError(msg.id, -32603, 'Internal error');
        }
      })
      .finally(() => inflight.delete(p));
    inflight.add(p);
  }

  process.stdin.on('data', (chunk) => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf('\n')) !== -1) {
      const raw = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      processLine(raw);
    }
  });

  process.stdin.on('end', async () => {
    // Flush a trailing line with no final newline, then let in-flight work settle.
    if (buffer.length) { processLine(buffer); buffer = ''; }
    while (inflight.size) await Promise.allSettled(Array.from(inflight));
    log('stdin closed — exiting');
    process.exit(0);
  });

  process.stdin.on('error', (err) => {
    log('stdin error:', err && err.message);
  });
}

if (require.main === module) {
  start();
}

module.exports = { TOOLS, dispatch, SERVER_NAME, SERVER_VERSION, PROTOCOL_VERSION };
