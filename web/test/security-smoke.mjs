// Security smoke test for the Reprise / Claude Code Session Indexer web server.
// Boots the server against an isolated empty data root and asserts the localhost
// hardening actually fires. Exits non-zero on any failure so CI catches regressions.
//
// Run:  node web/test/security-smoke.mjs
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// fetch() forbids overriding the Host header, so DNS-rebinding tests need a raw
// request. Returns { status } for a GET with arbitrary headers.
function rawGet(pathname, headers) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host: '127.0.0.1', port: PORT, path: pathname, method: 'GET', headers },
      (res) => { res.resume(); resolve({ status: res.statusCode }); },
    );
    req.on('error', reject);
    req.end();
  });
}

const here = path.dirname(fileURLToPath(import.meta.url));
const SERVER = path.join(here, '..', 'server.js');
const PORT = 4788;
const BASE = `http://127.0.0.1:${PORT}`;

const dataDir = mkdtempSync(path.join(tmpdir(), 'csi-smoke-'));

const proc = spawn(process.execPath, [SERVER], {
  env: { ...process.env, PORT: String(PORT), CSI_CLAUDE_DIR: dataDir },
  stdio: ['ignore', 'ignore', 'inherit'],
});

const failures = [];
function check(cond, label) {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`);
  if (!cond) failures.push(label);
}

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try {
      const r = await fetch(`${BASE}/api/sessions`, { headers: { 'X-CSI-Request': '1' } });
      if (r.status === 200) return;
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('server did not start');
}

try {
  await waitForServer();

  // 1. Legit same-origin API call with the custom header → 200
  let r = await fetch(`${BASE}/api/sessions`, { headers: { 'X-CSI-Request': '1' } });
  check(r.status === 200, 'legit API call (loopback host + X-CSI-Request) → 200');

  // 2. Missing custom header → 403 (CSRF gate)
  r = await fetch(`${BASE}/api/sessions`);
  check(r.status === 403, 'API call without X-CSI-Request → 403 (CSRF)');

  // 3. Attacker Host header (DNS-rebinding) → 403, even for static.
  //    Uses a raw request because fetch() won't forge Host.
  const rebind = await rawGet('/', { Host: 'evil.example', 'X-CSI-Request': '1' });
  check(rebind.status === 403, 'attacker Host header → 403 (rebinding)');

  // 4. Cross-origin Origin → 403
  r = await fetch(`${BASE}/api/sessions`, {
    headers: { 'X-CSI-Request': '1', Origin: 'https://evil.example' },
  });
  check(r.status === 403, 'cross-origin Origin → 403');

  // 5. Non-UUID session id → 400 (route gate, blocks traversal + amplification)
  r = await fetch(`${BASE}/api/sessions/not-a-uuid/preview`, { headers: { 'X-CSI-Request': '1' } });
  check(r.status === 400, 'non-UUID session id → 400 (BAD_ID gate)');

  // 6. Path-traversal-shaped id → 400
  r = await fetch(`${BASE}/api/sessions/..%2f..%2fetc/preview`, { headers: { 'X-CSI-Request': '1' } });
  check(r.status === 400, 'traversal-shaped session id → 400');

  // 7. Hardening headers present on the SPA + CSP
  r = await fetch(`${BASE}/`, { headers: { 'X-CSI-Request': '1' } });
  check(r.headers.get('x-content-type-options') === 'nosniff', 'X-Content-Type-Options: nosniff on /');
  check(r.headers.get('x-frame-options') === 'DENY', 'X-Frame-Options: DENY on /');
  check((r.headers.get('content-security-policy') || '').includes("default-src 'self'"), 'CSP on SPA HTML');

  // 8. No CORS headers leak anywhere
  r = await fetch(`${BASE}/api/sessions`, { headers: { 'X-CSI-Request': '1' } });
  check(!r.headers.get('access-control-allow-origin'), 'no Access-Control-Allow-Origin header');
} catch (err) {
  console.error('smoke test error:', err.message);
  failures.push('harness: ' + err.message);
} finally {
  proc.kill('SIGKILL');
}

console.log(failures.length ? `\nWEB SECURITY SMOKE: ${failures.length} FAILURE(S)` : '\nWEB SECURITY SMOKE: ALL PASS');
process.exit(failures.length ? 1 : 0);
