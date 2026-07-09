/* =========================================================================
   Claude Sessions — Web  ·  frontend
   Zero dependencies, no build step, fully offline.
   ========================================================================= */
(function () {
  'use strict';

  // ---- inline lucide-style icons (paths authored here; no external assets) ----
  const ICONS = {
    layers: '<path d="M12 2 2 7l10 5 10-5-10-5Z"/><path d="m2 17 10 5 10-5"/><path d="m2 12 10 5 10-5"/>',
    tag: '<path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42Z"/><circle cx="7.5" cy="7.5" r="1.2" fill="currentColor"/>',
    pulse: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    sort: '<path d="m3 16 4 4 4-4"/><path d="M7 20V4"/><path d="M11 4h10"/><path d="M11 8h7"/><path d="M11 12h4"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>',
    moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    refresh: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
    menu: '<path d="M3 12h18M3 6h18M3 18h18"/>',
    copy: '<rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    terminal: '<path d="m4 17 6-6-6-6"/><path d="M12 19h8"/>',
    play: '<path d="m6 3 14 9-14 9V3Z"/>',
    sparkles: '<path d="M9.94 15.5A2 2 0 0 0 8.5 14.06l-6.14-1.58a.5.5 0 0 1 0-.96L8.5 9.94A2 2 0 0 0 9.94 8.5l1.58-6.14a.5.5 0 0 1 .96 0L14.06 8.5A2 2 0 0 0 15.5 9.94l6.14 1.58a.5.5 0 0 1 0 .96L15.5 14.06a2 2 0 0 0-1.44 1.44l-1.58 6.14a.5.5 0 0 1-.96 0z"/><path d="M20 3v4M22 5h-4"/>',
    folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    branch: '<line x1="6" x2="6" y1="3" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>',
    clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    cpu: '<rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/><path d="M15 2v2M15 20v2M2 15h2M2 9h2M20 15h2M20 9h2M9 2v2M9 20v2"/>',
    message: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
    hash: '<line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/><line x1="10" x2="8" y1="3" y2="21"/><line x1="16" x2="14" y1="3" y2="21"/>',
    arrowLeft: '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    package: '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/>',
    calendar: '<rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18M8 2v4M16 2v4"/>',
    inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
    theme: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
  };
  function icon(name) {
    return '<svg class="ic" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + (ICONS[name] || '') + '</svg>';
  }

  const PALETTE = ['#E38561', '#E0A458', '#CDBE5B', '#8FBF7F', '#57B6A6', '#5CA0D8', '#8B8FE6', '#BE83DA', '#E07FA6', '#D77F5C'];
  function projColor(name) {
    let h = 0;
    const s = name || '';
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
    return PALETTE[h % PALETTE.length];
  }

  // ---- helpers ----
  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function relTime(iso) {
    if (!iso) return '—';
    const t = Date.parse(iso);
    if (isNaN(t)) return '—';
    const diff = Date.now() - t;
    const s = Math.floor(diff / 1000);
    if (s < 45) return 'just now';
    const m = Math.floor(s / 60);
    if (m < 60) return m + 'm ago';
    const h = Math.floor(m / 60);
    if (h < 24) return h + 'h ago';
    const d = Math.floor(h / 24);
    if (d < 7) return d + 'd ago';
    const w = Math.floor(d / 7);
    if (d < 30) return w + 'w ago';
    const mo = Math.floor(d / 30);
    if (mo < 12) return mo + 'mo ago';
    return Math.floor(d / 365) + 'y ago';
  }
  function fmtDateTime(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    if (isNaN(d)) return '—';
    return d.toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
  }
  function fmtBytes(n) {
    if (!n && n !== 0) return '—';
    if (n < 1024) return n + ' B';
    if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
    return (n / 1048576).toFixed(1) + ' MB';
  }
  function shortModel(m) {
    if (!m) return null;
    return m.replace(/^claude-/, '').replace(/-\d{8}$/, '');
  }

  // ---- state ----
  const state = {
    sessions: [],
    filter: 'all',
    project: null,
    sort: 'activity',
    search: '',
    selectedId: null,
    loading: true,
    scannedAt: null,
    previews: {},
    generating: {},
    summaryErr: {},
  };

  // ---- DOM refs ----
  const app = $('#app');
  const elProjectList = $('#projectList');
  const elSessionRows = $('#sessionRows');
  const elSkeleton = $('#skeletonList');
  const elListEmpty = $('#listEmpty');
  const elListContext = $('#listContext');
  const elSearch = $('#search');
  const elSearchClear = $('#searchClear');
  const elOverview = $('#overview');
  const elDetail = $('#detail');
  const elStatus = $('#statusHint');
  const elSortLabel = $('#sortLabel');
  const elSortMenu = $('#sortMenu');

  const SORT_LABELS = { activity: 'Last activity', created: 'Date created', messages: 'Most messages', title: 'Title A–Z' };

  // hydrate all static [data-ico]
  function hydrateIcons(root) {
    $$('[data-ico]', root).forEach((el) => { if (!el.dataset.hydrated) { el.innerHTML = icon(el.dataset.ico); el.dataset.hydrated = '1'; } });
  }

  function status(msg, kind) {
    elStatus.textContent = msg;
    elStatus.className = kind || '';
    if (kind === 'ok' || kind === 'err') {
      clearTimeout(status._t);
      status._t = setTimeout(() => { elStatus.textContent = 'Ready'; elStatus.className = ''; }, 4000);
    }
  }

  // ---- data load ----
  async function loadSessions(isInitial) {
    try {
      const r = await fetch('/api/sessions', { cache: 'no-store' });
      const data = await r.json();
      state.sessions = data.sessions || [];
      state.scannedAt = data.scannedAt;
      state.loading = false;
      elSkeleton.hidden = true;
      elSessionRows.hidden = false;
      renderSidebar();
      renderList();
      if (state.selectedId) {
        const s = state.sessions.find((x) => x.sessionId === state.selectedId);
        if (s) renderDetail(s); else showOverview();
      } else {
        showOverview();
      }
      status(state.sessions.length + ' sessions loaded', isInitial ? 'ok' : null);
    } catch (e) {
      state.loading = false;
      elSkeleton.hidden = true;
      status('Failed to load sessions', 'err');
      console.error(e);
    }
  }

  // ---- derived ----
  function projectGroups() {
    const map = new Map();
    for (const s of state.sessions) {
      const name = s.projectName || s.projectKey;
      if (!map.has(name)) map.set(name, { name, count: 0, key: s.projectKey, cwd: s.cwd, last: 0 });
      const g = map.get(name);
      g.count++;
      const t = Date.parse(s.lastActivityAt) || 0;
      if (t > g.last) g.last = t;
    }
    return Array.from(map.values()).sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  }
  function counts() {
    return {
      all: state.sessions.length,
      named: state.sessions.filter((s) => s.customTitle).length,
      running: state.sessions.filter((s) => s.running).length,
    };
  }
  function summaryLead(s) {
    if (!s.summary || !s.summary.text) return null;
    const firstLine = s.summary.text.split('\n').map((l) => l.trim()).filter(Boolean)[0] || '';
    return firstLine.replace(/^-\s*/, '');
  }
  function currentList() {
    let list = state.sessions.slice();
    if (state.filter === 'named') list = list.filter((s) => s.customTitle);
    else if (state.filter === 'running') list = list.filter((s) => s.running);
    else if (state.filter === 'project' && state.project) list = list.filter((s) => (s.projectName || s.projectKey) === state.project);

    const q = state.search.trim().toLowerCase();
    if (q) {
      list = list.filter((s) => {
        return (s.title || '').toLowerCase().includes(q)
          || (s.customTitle || '').toLowerCase().includes(q)
          || (s.aiTitle || '').toLowerCase().includes(q)
          || (s.firstPrompt || '').toLowerCase().includes(q)
          || (s.projectName || '').toLowerCase().includes(q)
          || (s.sessionId || '').toLowerCase().startsWith(q)
          || (s.summary && s.summary.text ? s.summary.text.toLowerCase().includes(q) : false);
      });
    }
    const val = (s, f) => Date.parse(s[f]) || 0;
    if (state.sort === 'activity') list.sort((a, b) => val(b, 'lastActivityAt') - val(a, 'lastActivityAt'));
    else if (state.sort === 'created') list.sort((a, b) => val(b, 'createdAt') - val(a, 'createdAt'));
    else if (state.sort === 'messages') list.sort((a, b) => b.userMessageCount - a.userMessageCount);
    else if (state.sort === 'title') list.sort((a, b) => (a.title || '').localeCompare(b.title || ''));
    return list;
  }

  // ---- render: sidebar ----
  function renderSidebar() {
    const c = counts();
    $('[data-count="all"]').textContent = c.all;
    $('[data-count="named"]').textContent = c.named;
    $('[data-count="running"]').textContent = c.running;

    const groups = projectGroups();
    elProjectList.innerHTML = groups.map((g) => {
      const col = projColor(g.name);
      const active = state.filter === 'project' && state.project === g.name;
      return `<button class="project-item" data-proj="${esc(g.name)}" data-active="${active}">
        <span class="dot" style="background:${col};color:${col}"></span>
        <span class="nav-name">${esc(g.name)}</span>
        <span class="nav-count tnum">${g.count}</span>
      </button>`;
    }).join('');
  }

  // ---- render: list ----
  function rowHTML(s) {
    const col = projColor(s.projectName || s.projectKey);
    const sub = summaryLead(s) || s.firstPrompt || 'No prompt captured for this session.';
    const isSummary = !!summaryLead(s);
    const badges = [];
    if (s.running) badges.push('<span class="badge badge-run"><span class="run-dot"></span>Running</span>');
    if (s.customTitle) badges.push('<span class="badge badge-named">Named</span>');
    return `<button class="srow" data-id="${esc(s.sessionId)}" data-active="${s.sessionId === state.selectedId}">
      <div class="srow-top">
        <span class="srow-title">${esc(s.title)}</span>
        ${badges.join('')}
      </div>
      <div class="srow-sub ${isSummary ? 'is-summary' : ''}">${esc(sub)}</div>
      <div class="srow-meta">
        <span class="srow-proj"><span class="dot" style="background:${col}"></span><span class="pname">${esc(s.projectName || s.projectKey)}</span></span>
        <span class="srow-dotsep">·</span>
        <span class="srow-time">${relTime(s.lastActivityAt)}</span>
        <span class="srow-chip tnum" title="${s.userMessageCount} prompts">${icon('message')}${s.userMessageCount}</span>
      </div>
    </button>`;
  }
  function renderList() {
    const list = currentList();
    const label = state.filter === 'project' ? state.project
      : state.filter === 'named' ? 'Named'
      : state.filter === 'running' ? 'Running'
      : 'All Sessions';
    elListContext.innerHTML = `<b>${esc(label)}</b> · ${list.length} session${list.length === 1 ? '' : 's'}`;

    if (!list.length) {
      elSessionRows.hidden = true;
      elListEmpty.hidden = false;
      const searching = !!state.search.trim();
      elListEmpty.innerHTML = `
        <span class="empty-ico">${icon(searching ? 'search' : 'inbox')}</span>
        <div class="empty-title">${searching ? 'No matches' : 'Nothing here yet'}</div>
        <div class="empty-sub">${searching ? 'Try a different search term or clear the filter.' : 'Start a session with the Claude Code CLI and it will show up here.'}</div>`;
      return;
    }
    elListEmpty.hidden = true;
    elSessionRows.hidden = false;
    elSessionRows.innerHTML = list.map(rowHTML).join('');
    hydrateIcons(elSessionRows);
  }

  // ---- render: overview ----
  function showOverview() {
    state.selectedId = null;
    $$('.srow').forEach((r) => (r.dataset.active = 'false'));
    elDetail.hidden = true;
    elOverview.hidden = false;
    renderOverview();
    app.dataset.detailOpen = 'false';
  }
  function renderOverview() {
    const c = counts();
    const groups = projectGroups();
    const maxCount = groups.length ? groups[0].count : 1;
    const recents = state.sessions.slice().sort((a, b) => (Date.parse(b.lastActivityAt) || 0) - (Date.parse(a.lastActivityAt) || 0)).slice(0, 6);
    const hour = new Date().getHours();
    const greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';

    elOverview.innerHTML = `
      <div class="ov-hello">${greeting}</div>
      <h1 class="ov-title">Your <span class="grad">Claude Code</span> sessions</h1>
      <p class="ov-lead">Every conversation from the CLI, indexed and searchable. Pick one to preview, summarize, or resume right where you left off.</p>

      <div class="stat-grid">
        <div class="stat-tile accent">
          <div class="stat-ico"><span>${icon('layers')}</span></div>
          <div class="stat-num tnum">${c.all}</div>
          <div class="stat-lbl">Total sessions</div>
        </div>
        <div class="stat-tile">
          <div class="stat-ico"><span>${icon('tag')}</span></div>
          <div class="stat-num tnum">${c.named}</div>
          <div class="stat-lbl">Named</div>
        </div>
        <div class="stat-tile run">
          <div class="stat-ico"><span>${icon('pulse')}</span></div>
          <div class="stat-num tnum">${c.running}</div>
          <div class="stat-lbl">Running now</div>
        </div>
        <div class="stat-tile">
          <div class="stat-ico"><span>${icon('package')}</span></div>
          <div class="stat-num tnum">${groups.length}</div>
          <div class="stat-lbl">Projects</div>
        </div>
      </div>

      <div class="ov-cols">
        <div class="ov-card">
          <h3>Top projects</h3>
          ${groups.slice(0, 7).map((g) => {
            const col = projColor(g.name);
            const pct = Math.max(6, Math.round((g.count / maxCount) * 100));
            return `<button class="bar-row" data-proj="${esc(g.name)}" style="width:100%;text-align:left">
              <span class="bar-name"><span class="dot" style="background:${col}"></span>${esc(g.name)}</span>
              <span class="bar-track"><span class="bar-fill" style="width:${pct}%;background:${col}"></span></span>
              <span class="bar-val tnum">${g.count}</span>
            </button>`;
          }).join('') || '<div class="empty-sub">No projects yet.</div>'}
        </div>
        <div class="ov-card">
          <h3>Recent sessions</h3>
          ${recents.map((s) => {
            const col = projColor(s.projectName || s.projectKey);
            return `<button class="recent-item" data-id="${esc(s.sessionId)}">
              <span class="dot" style="background:${col}"></span>
              <span class="r-title">${esc(s.title)}</span>
              ${s.running ? '<span class="run-dot" style="margin-right:2px"></span>' : ''}
              <span class="r-time">${relTime(s.lastActivityAt)}</span>
            </button>`;
          }).join('') || '<div class="empty-sub">No sessions yet.</div>'}
        </div>
      </div>`;
  }

  // ---- render: detail ----
  function selectSession(id, opts) {
    const s = state.sessions.find((x) => x.sessionId === id);
    if (!s) return;
    state.selectedId = id;
    $$('.srow').forEach((r) => (r.dataset.active = String(r.dataset.id === id)));
    if (opts && opts.scroll) {
      const row = $('.srow[data-id="' + cssEsc(id) + '"]');
      if (row) row.scrollIntoView({ block: 'nearest' });
    }
    renderDetail(s);
    app.dataset.detailOpen = 'true';
  }
  function cssEsc(s) { return String(s).replace(/["\\]/g, '\\$&'); }

  function formatSummary(text) {
    const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);
    const lead = [];
    const bullets = [];
    for (const l of lines) {
      if (/^[-•*]\s+/.test(l)) bullets.push(l.replace(/^[-•*]\s+/, ''));
      else bullets.length ? bullets.push(l) : lead.push(l);
    }
    let html = '';
    if (lead.length) html += `<div class="sc-lead">${esc(lead.join(' '))}</div>`;
    for (const b of bullets) html += `<div class="sum-bullet">${esc(b)}</div>`;
    return html || esc(text);
  }

  function summaryCardHTML(s) {
    if (state.generating[s.sessionId]) {
      return `<div class="sc-loading"><span class="spinner"></span><span>Summarizing with <b>claude&nbsp;·&nbsp;haiku</b><span class="sc-dots"><span></span><span></span><span></span></span></span></div>`;
    }
    if (s.summary && s.summary.text) {
      return `<div class="sc-body">${formatSummary(s.summary.text)}</div>
        <div class="sc-meta">${icon('clock')}<span>Generated ${relTime(s.summary.generatedAt)}</span></div>`;
    }
    const err = state.summaryErr[s.sessionId];
    return `<div class="sc-empty">
        ${err ? `<div class="sc-error">${esc(err)}</div>` : '<p>Let Claude read this transcript and write a tight summary of what happened — goal, outcome, and key decisions.</p>'}
      </div>`;
  }

  function renderDetail(s) {
    elOverview.hidden = true;
    elDetail.hidden = false;
    const col = projColor(s.projectName || s.projectKey);
    const badges = [];
    if (s.running) badges.push('<span class="badge badge-run"><span class="run-dot"></span>Running</span>');
    if (s.customTitle) badges.push('<span class="badge badge-named">Named</span>');
    const model = shortModel(s.model);

    const gridCells = [];
    gridCells.push(cell('Session ID', s.sessionId.slice(0, 8) + '…' + s.sessionId.slice(-4), 'mono'));
    if (model) gridCells.push(cell('Model', model, 'mono'));
    gridCells.push(cell('Prompts', s.userMessageCount + ' user · ' + s.assistantMessageCount + ' assistant'));
    if (s.gitBranch) gridCells.push(cell('Branch', s.gitBranch, 'mono'));
    gridCells.push(cell('Created', fmtDateTime(s.createdAt)));
    gridCells.push(cell('Last activity', fmtDateTime(s.lastActivityAt)));
    if (s.cliVersion) gridCells.push(cell('CLI version', 'v' + s.cliVersion, 'mono'));
    gridCells.push(cell('Transcript size', fmtBytes(s.fileSize)));

    const hasSummary = s.summary && s.summary.text;

    elDetail.innerHTML = `
      <button class="btn-back" id="detailBack" style="display:none"></button>
      <div class="d-badges">${badges.join('') || '<span class="badge" style="color:var(--text-faint);background:var(--surface-3)">Session</span>'}</div>
      <h1 class="d-title">${esc(s.title)}</h1>
      <div class="d-projchip">${icon('folder')}<span class="dot" style="background:${col}"></span><span class="p">${esc(s.cwd || s.projectName || s.projectKey)}</span></div>

      <div class="d-section">
        <div class="d-section-h">${icon('terminal')} Resume command</div>
        <div class="cmd-block">
          <div class="cmd-bar"><span class="cmd-dots"><i></i><i></i><i></i></span><span class="cmd-label">terminal</span></div>
          <div class="cmd-body">
            <div class="cmd-text"><span class="prompt">$ </span>${esc(s.resumeCommand)}</div>
            <button class="cmd-copy" id="cmdCopy" title="Copy command">${icon('copy')}</button>
          </div>
        </div>
        <div class="d-actions">
          <button class="btn btn-primary" id="resumeBtn">${icon('play')} Resume in Terminal</button>
          <button class="btn btn-ghost" id="copyCmdBtn">${icon('copy')} Copy command</button>
          <button class="btn btn-ghost" id="copyIdBtn">${icon('hash')} Copy Session ID</button>
        </div>
      </div>

      <div class="d-section">
        <div class="summary-card" id="summaryCard">
          <div class="sc-head">
            <div class="sc-title"><span class="spark"><span>${icon('sparkles')}</span></span> AI Summary</div>
            <button class="btn btn-ghost" id="genSummaryBtn" style="padding:6px 12px;font-size:12px">
              ${icon(hasSummary ? 'refresh' : 'zap')} ${hasSummary ? 'Regenerate' : 'Generate'}
            </button>
          </div>
          <div id="summaryBody">${summaryCardHTML(s)}</div>
        </div>
      </div>

      <div class="d-section">
        <div class="d-section-h">${icon('layers')} Details</div>
        <div class="detail-grid">${gridCells.join('')}</div>
      </div>

      <div class="d-section">
        <div class="d-section-h">${icon('message')} Conversation preview</div>
        <div class="chat" id="chat">
          <div class="preview-loading">
            <div class="pl-bubble u"></div><div class="pl-bubble a"></div><div class="pl-bubble u"></div>
          </div>
        </div>
      </div>`;

    hydrateIcons(elDetail);
    wireDetail(s);
    loadPreview(s);
    elDetail.parentElement.scrollTop = 0;
  }

  function cell(k, v, cls) {
    return `<div class="dg-cell"><div class="dg-k">${esc(k)}</div><div class="dg-v ${cls || ''}">${esc(v)}</div></div>`;
  }

  function wireDetail(s) {
    const copyCmd = () => copyText(s.resumeCommand, null, 'Command copied');
    $('#cmdCopy').addEventListener('click', (e) => copyText(s.resumeCommand, e.currentTarget));
    $('#copyCmdBtn').addEventListener('click', (e) => copyText(s.resumeCommand, e.currentTarget, 'Command copied'));
    $('#copyIdBtn').addEventListener('click', (e) => copyText(s.sessionId, e.currentTarget, 'Session ID copied'));
    $('#resumeBtn').addEventListener('click', () => resume(s.sessionId));
    $('#genSummaryBtn').addEventListener('click', () => genSummary(s.sessionId));
  }

  async function loadPreview(s) {
    const chat = $('#chat');
    if (state.previews[s.sessionId]) { renderChat(chat, state.previews[s.sessionId]); return; }
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(s.sessionId) + '/preview', { cache: 'no-store' });
      const data = await r.json();
      state.previews[s.sessionId] = data.messages || [];
      if (state.selectedId === s.sessionId) renderChat(chat, state.previews[s.sessionId]);
    } catch (e) {
      if (chat) chat.innerHTML = '<div class="chat-more">Could not load conversation preview.</div>';
    }
  }
  function renderChat(chat, messages) {
    if (!chat) return;
    if (!messages.length) { chat.innerHTML = '<div class="chat-more">No previewable messages in this transcript.</div>'; return; }
    const CAP = 60;
    const shown = messages.slice(0, CAP);
    chat.innerHTML = shown.map((m) => {
      const role = m.role === 'user' ? 'user' : 'assistant';
      return `<div class="bubble-wrap ${role}">
        <div class="bubble-role">${role === 'user' ? 'You' : 'Claude'}</div>
        <div class="bubble">${esc(m.text)}</div>
        ${m.timestamp ? `<div class="bubble-time">${fmtDateTime(m.timestamp)}</div>` : ''}
      </div>`;
    }).join('') + (messages.length > CAP ? `<div class="chat-more">+ ${messages.length - CAP} more messages in the full transcript</div>` : '');
  }

  // ---- actions ----
  function copyText(text, btnEl, statusMsg) {
    const done = () => {
      status(statusMsg || 'Copied to clipboard', 'ok');
      if (btnEl) {
        const orig = btnEl.innerHTML;
        btnEl.classList.add('copied');
        const isIconOnly = btnEl.classList.contains('cmd-copy');
        btnEl.innerHTML = isIconOnly ? icon('check') : icon('check') + ' Copied';
        setTimeout(() => { btnEl.innerHTML = orig; btnEl.classList.remove('copied'); }, 1500);
      }
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done));
    } else fallbackCopy(text, done);
  }
  function fallbackCopy(text, done) {
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); done(); } catch (e) { status('Copy failed', 'err'); }
    document.body.removeChild(ta);
  }

  async function genSummary(id) {
    if (state.generating[id]) return;
    state.generating[id] = true;
    state.summaryErr[id] = null;
    const s = state.sessions.find((x) => x.sessionId === id);
    if (state.selectedId === id) { $('#summaryBody').innerHTML = summaryCardHTML(s); hydrateIcons($('#summaryBody')); }
    const btn = $('#genSummaryBtn'); if (btn) btn.disabled = true;
    status('Generating summary via claude CLI…');
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(id) + '/summary', { method: 'POST' });
      const data = await r.json();
      state.generating[id] = false;
      if (!r.ok) throw new Error(data.error || 'Summary failed');
      s.summary = { text: data.text, generatedAt: data.generatedAt };
      status('Summary ready', 'ok');
      if (state.selectedId === id) renderDetail(s);
      renderList();
    } catch (e) {
      state.generating[id] = false;
      state.summaryErr[id] = e.message;
      status('Summary failed', 'err');
      if (state.selectedId === id && s) renderDetail(s);
    }
  }

  async function resume(id) {
    const s = state.sessions.find((x) => x.sessionId === id);
    if (!s) return;
    status('Opening terminal…');
    const btn = $('#resumeBtn'); if (btn) { btn.disabled = true; }
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(id) + '/resume', { method: 'POST' });
      const data = await r.json();
      if (!r.ok || !data.ok) throw new Error(data.error || 'Resume failed');
      status('Terminal opened — resuming session', 'ok');
    } catch (e) {
      status('Resume failed: ' + e.message, 'err');
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  // ---- filters / nav ----
  function setFilter(filter, project) {
    state.filter = filter;
    state.project = project || null;
    $$('.nav-item').forEach((n) => (n.dataset.active = String(n.dataset.filter === filter && filter !== 'project')));
    renderSidebar();
    renderList();
  }

  // ---- theme ----
  function applyTheme(theme) {
    if (theme) document.documentElement.setAttribute('data-theme', theme);
    else document.documentElement.removeAttribute('data-theme');
    const effective = theme || (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    const btn = $('#themeToggle .nav-ico');
    if (btn) btn.innerHTML = icon(effective === 'light' ? 'moon' : 'sun');
  }
  function initTheme() {
    const saved = localStorage.getItem('cs-theme');
    applyTheme(saved || null);
  }
  function toggleTheme() {
    const cur = document.documentElement.getAttribute('data-theme')
      || (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    const next = cur === 'light' ? 'dark' : 'light';
    localStorage.setItem('cs-theme', next);
    applyTheme(next);
  }

  // ---- keyboard ----
  function moveSelection(dir) {
    const list = currentList();
    if (!list.length) return;
    let idx = list.findIndex((s) => s.sessionId === state.selectedId);
    idx = idx === -1 ? (dir > 0 ? 0 : list.length - 1) : idx + dir;
    idx = Math.max(0, Math.min(list.length - 1, idx));
    selectSession(list[idx].sessionId, { scroll: true });
  }

  // ---- events ----
  function bind() {
    $$('.nav-item').forEach((n) => n.addEventListener('click', () => setFilter(n.dataset.filter)));
    elProjectList.addEventListener('click', (e) => {
      const b = e.target.closest('.project-item'); if (b) setFilter('project', b.dataset.proj);
    });
    elSessionRows.addEventListener('click', (e) => {
      const b = e.target.closest('.srow'); if (b) selectSession(b.dataset.id);
    });
    elOverview.addEventListener('click', (e) => {
      const rec = e.target.closest('.recent-item'); if (rec) { selectSession(rec.dataset.id); return; }
      const bar = e.target.closest('.bar-row'); if (bar) setFilter('project', bar.dataset.proj);
    });

    elSearch.addEventListener('input', () => {
      state.search = elSearch.value;
      elSearchClear.hidden = !elSearch.value;
      renderList();
    });
    elSearchClear.addEventListener('click', () => { elSearch.value = ''; state.search = ''; elSearchClear.hidden = true; renderList(); elSearch.focus(); });

    $('#sortBtn').addEventListener('click', (e) => { e.stopPropagation(); elSortMenu.hidden = !elSortMenu.hidden; });
    elSortMenu.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      state.sort = b.dataset.sort;
      $$('button', elSortMenu).forEach((x) => (x.dataset.active = String(x === b)));
      elSortLabel.textContent = SORT_LABELS[state.sort];
      elSortMenu.hidden = true;
      renderList();
    });
    document.addEventListener('click', () => { elSortMenu.hidden = true; });

    $('#themeToggle').addEventListener('click', toggleTheme);
    $('#refreshBtn').addEventListener('click', (e) => {
      const b = e.currentTarget; b.classList.add('spinning');
      status('Rescanning…');
      loadSessions().finally(() => setTimeout(() => b.classList.remove('spinning'), 500));
    });

    $('#mobileMenuBtn').addEventListener('click', () => {
      app.dataset.navOpen = app.dataset.navOpen === 'true' ? 'false' : 'true';
    });
    app.addEventListener('click', (e) => {
      // scrim closes mobile sidebar
      if (app.dataset.navOpen === 'true' && e.target === app) app.dataset.navOpen = 'false';
    });

    document.addEventListener('keydown', (e) => {
      const typing = document.activeElement && (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA');
      if (e.key === '/' && !typing) { e.preventDefault(); elSearch.focus(); elSearch.select(); return; }
      if (e.key === 'Escape') {
        if (typing) { elSearch.blur(); return; }
        if (app.dataset.detailOpen === 'true' && window.innerWidth <= 900) { showOverview(); return; }
      }
      if (typing) return;
      if (e.key === 'ArrowDown') { e.preventDefault(); moveSelection(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); moveSelection(-1); }
      else if (e.key === 'Enter') { if (state.selectedId) selectSession(state.selectedId); }
      else if ((e.key === 'r' || e.key === 'R') && state.selectedId) { resume(state.selectedId); }
      else if ((e.key === 'c' || e.key === 'C') && state.selectedId) {
        const s = state.sessions.find((x) => x.sessionId === state.selectedId); if (s) copyText(s.resumeCommand, null, 'Command copied');
      }
    });

    window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => {
      if (!localStorage.getItem('cs-theme')) applyTheme(null);
    });
  }

  // ---- skeleton ----
  function renderSkeleton() {
    let html = '';
    for (let i = 0; i < 8; i++) {
      html += `<div class="skel-row">
        <div class="skel-line skel-w-70"></div>
        <div class="skel-line skel-w-90"></div>
        <div class="skel-line skel-w-40"></div>
      </div>`;
    }
    elSkeleton.innerHTML = html;
  }

  // ---- init ----
  function init() {
    initTheme();
    hydrateIcons(document);
    renderSkeleton();
    bind();
    app.dataset.loading = 'false';
    loadSessions(true);
    // lightweight running-state refresh
    setInterval(() => { if (!state.loading) loadSessions(); }, 20000);
  }
  document.addEventListener('DOMContentLoaded', init);
})();
