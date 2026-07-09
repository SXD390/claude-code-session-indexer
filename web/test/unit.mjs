// Unit tests for the web server's pure functions: secret redaction, pricing,
// and the handoff PROGRESS.md / CLAUDE.md upsert logic. No server, no network.
//
// Run:  node web/test/unit.mjs
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const S = require(path.join(here, '..', 'server.js'));

const failures = [];
function eq(actual, expected, label) {
  const ok = actual === expected;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}`);
  if (!ok) { failures.push(label); console.log(`      expected: ${JSON.stringify(expected)}\n      actual:   ${JSON.stringify(actual)}`); }
}
function ok(cond, label) { eq(!!cond, true, label); }

// --- Redaction: secrets scrubbed, prose/code untouched ---
const R = S.redactSecrets;
ok(!R('sk-ant-api03-abcdefghij0123456789klmnop').includes('abcdefghij'), 'redacts sk- key');
ok(R('token ghp_ABCDEFGHIJKLMNOPQRST0123456789').includes('[REDACTED]'), 'redacts GitHub token');
ok(R('AKIAIOSFODNN7EXAMPLE').includes('[REDACTED]'), 'redacts AWS key id');
eq(R('DB_PASSWORD=hunter2secret').startsWith('DB_PASSWORD='), true, 'keeps key name in assignment');
ok(R('DB_PASSWORD=hunter2secret').includes('[REDACTED]'), 'redacts assignment value');
ok(R('Authorization: Bearer abcdefghijklmnopqrstuvwx').includes('[REDACTED]'), 'redacts bearer token');
eq(R('call the search API with a function'), 'call the search API with a function', 'leaves prose untouched');
eq(R('edit src/main.ts and run npm test'), 'edit src/main.ts and run npm test', 'leaves code/paths untouched');
eq(R(''), '', 'empty string safe');

// --- Pricing: prefix match, first-match-wins, fallback ---
eq(S.rateFor('claude-fable-5')[1], 10.0, 'fable input rate');
eq(S.rateFor('claude-opus-4-8')[1], 5.0, 'opus-4-8 input rate (generic opus)');
eq(S.rateFor('claude-opus-4-1-20250805')[1], 15.0, 'opus-4-1 input rate (specific before generic)');
eq(S.rateFor('claude-haiku-4-5-20251001')[1], 1.0, 'haiku input rate');
eq(S.rateFor('some-unknown-model')[0], '(other)', 'unknown model → fallback');
eq(S.modelTier('claude-fable-5'), 'Fable', 'fable tier');
eq(S.modelTier('claude-sonnet-4-6'), 'Sonnet', 'sonnet tier');

// --- Handoff PROGRESS.md: prepend under title, preserve existing ---
{
  const existing = '# Progress — demo\n\n## 2026-07-01 — old thing\n- did a thing\n';
  const out = S.insertProgressSection(existing, '## 2026-07-08 — new thing\n- did a new thing');
  ok(out.startsWith('# Progress — demo'), 'PROGRESS keeps its title first');
  ok(out.indexOf('2026-07-08') < out.indexOf('2026-07-01'), 'new section inserted above old');
  ok(out.includes('old thing'), 'PROGRESS preserves existing content');
}
{
  const out = S.insertProgressSection('', '## 2026-07-08 — first\n- x');
  ok(out.includes('2026-07-08'), 'PROGRESS on empty file works');
}

// --- Handoff CLAUDE.md: marker upsert is idempotent, preserves user content ---
{
  const block = `${S.HANDOFF_CLAUDE_START}\nmanaged v1\n${S.HANDOFF_CLAUDE_END}`;
  const user = '# CLAUDE.md\n\nMy own notes here.\n';
  const once = S.upsertClaudeBlock(user, block);
  ok(once.includes('My own notes here.'), 'CLAUDE.md preserves user notes');
  ok(once.includes('managed v1'), 'CLAUDE.md gets managed block');

  const block2 = `${S.HANDOFF_CLAUDE_START}\nmanaged v2\n${S.HANDOFF_CLAUDE_END}`;
  const twice = S.upsertClaudeBlock(once, block2);
  const starts = twice.split(S.HANDOFF_CLAUDE_START).length - 1;
  const ends = twice.split(S.HANDOFF_CLAUDE_END).length - 1;
  eq(starts, 1, 'exactly one start marker after re-run');
  eq(ends, 1, 'exactly one end marker after re-run');
  ok(twice.includes('managed v2') && !twice.includes('managed v1'), 'block replaced, not duplicated');
  ok(twice.includes('My own notes here.'), 'user notes still preserved after re-run');
}

// --- Handoff preview builders: the dry-run preview must merge EXACTLY like the
// write path, so buildProgressContent/buildClaudeContent are the same functions the
// preview and writeHandoff both call. Assert they agree with the primitives. ---
{
  const existing = '# Progress — demo\n\n## 2026-07-01 — old\n- a\n';
  const section = '## 2026-07-08 — new\n- b';
  eq(S.buildProgressContent(existing, section, 'demo'), S.insertProgressSection(existing, section),
     'buildProgressContent(existing) === insertProgressSection (preview == write)');
  const fresh = S.buildProgressContent(null, section, 'demo');
  ok(fresh.startsWith('# Progress — demo'), 'buildProgressContent(null) creates a titled PROGRESS.md');
  ok(fresh.includes('2026-07-08'), 'new-file PROGRESS includes the dated section');
}
{
  const user = '# CLAUDE.md\n\nMy notes.\n';
  const block = `${S.HANDOFF_CLAUDE_START}\ndurable knowledge\n${S.HANDOFF_CLAUDE_END}`;
  eq(S.buildClaudeContent(user, 'durable knowledge'), S.upsertClaudeBlock(user, block),
     'buildClaudeContent(existing) === upsertClaudeBlock (preview == write)');
  const freshC = S.buildClaudeContent(null, 'durable knowledge');
  ok(freshC.startsWith(S.HANDOFF_CLAUDE_START) && freshC.includes('durable knowledge'),
     'buildClaudeContent(null) creates a fresh marked CLAUDE.md');
}

console.log(failures.length ? `\nWEB UNIT: ${failures.length} FAILURE(S)` : '\nWEB UNIT: ALL PASS');
process.exit(failures.length ? 1 : 0);
