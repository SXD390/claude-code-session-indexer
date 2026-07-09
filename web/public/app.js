/* =========================================================================
   Claude Code Session Indexer — Web  ·  frontend
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
    chart: '<path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
    chevronR: '<path d="m9 18 6-6-6-6"/>',
    scan: '<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/><path d="M7 12h10"/>',
    book: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/>',
    coins: '<circle cx="8" cy="8" r="6"/><path d="M18.09 10.37A6 6 0 1 1 10.34 18"/><path d="M7 6h1v4"/><path d="m16.71 13.88.7.71-2.82 2.82"/>',
    gauge: '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
    timer: '<line x1="10" x2="14" y1="2" y2="2"/><line x1="12" x2="15" y1="14" y2="11"/><circle cx="12" cy="14" r="8"/>',
    database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5V19A9 3 0 0 0 21 19V5"/><path d="M3 12A9 3 0 0 0 21 12"/>',
    trophy: '<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/>',
    flame: '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>',
    dollar: '<line x1="12" x2="12" y1="2" y2="22"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
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
  // --- analytics formatting (mirrors the spec's number rules) ---
  function fmtTokens(n) {
    n = n || 0;
    if (n < 1000) return String(Math.round(n));
    if (n < 1e6) return (n / 1e3).toFixed(n < 1e4 ? 1 : 0).replace(/\.0$/, '') + 'K';
    if (n < 1e9) return (n / 1e6).toFixed(n < 1e7 ? 1 : 0).replace(/\.0$/, '') + 'M';
    return (n / 1e9).toFixed(1).replace(/\.0$/, '') + 'B';
  }
  function fmtCost(n) {
    n = n || 0;
    if (n > 0 && n < 1) return '$' + n.toFixed(4);
    return '$' + n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  function fmtDuration(sec) {
    sec = Math.round(sec || 0);
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    if (h > 0) return h + 'h ' + m + 'm';
    if (m > 0) return m + 'm';
    return sec + 's';
  }
  const TIER_COLOR = { Fable: '#E38561', Opus: '#8B8FE6', Sonnet: '#5CA0D8', Haiku: '#57B6A6', Other: '#E0A458' };
  function modelTier(m) {
    m = m || '';
    if (m.indexOf('claude-fable') === 0 || m.indexOf('claude-mythos') === 0) return 'Fable';
    if (m.indexOf('claude-opus') === 0) return 'Opus';
    if (m.indexOf('claude-sonnet') === 0) return 'Sonnet';
    if (m.indexOf('claude-haiku') === 0) return 'Haiku';
    return 'Other';
  }
  function tierColor(m) { return TIER_COLOR[modelTier(m)] || '#E0A458'; }
  const METRICS = {
    output: { key: 'output', label: 'Output tokens', color: 'var(--viz-output)', hex: '#E38561', kind: 'tokens' },
    input: { key: 'input', label: 'Input tokens', color: 'var(--viz-input)', hex: '#5CA0D8', kind: 'tokens' },
    cacheRead: { key: 'cacheRead', label: 'Cache read', color: 'var(--viz-cacheRead)', hex: '#57B6A6', kind: 'tokens' },
    cacheWrite: { key: 'cacheWrite', label: 'Cache write', color: 'var(--viz-cacheWrite)', hex: '#8B8FE6', kind: 'tokens' },
    cost: { key: 'cost', label: 'Est. cost', color: 'var(--viz-cost)', hex: '#E0A458', kind: 'cost' },
  };

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
    // signature features
    view: 'sessions',        // 'sessions' | 'insights'
    deepMode: false,
    deepResults: null,
    deepLoading: false,
    deepSeq: 0,
    usage: null,
    usageLoading: false,
    range: { preset: '30D', from: null, to: null },
    metric: 'output',
    journalProject: null,
    briefing: {},            // sessionId -> bool
    briefErr: {},
    usageDetail: {},         // sessionId -> per-session usage record
    handoffs: {},            // sessionId -> full handoff record (progress/claudeSection/kickstart + fs info)
    handoffLoading: {},      // sessionId -> bool (generating)
    handoffWriting: {},      // sessionId -> bool (writing files)
    handoffErr: {},          // sessionId -> error string
    handoffWritten: {},      // sessionId -> written path list
    includeClaudeMd: {},     // sessionId -> checkbox state
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
  const elJournal = $('#journal');
  const elInsights = $('#insightsPane');
  const elDeepToggle = $('#deepToggle');
  const elJournalBtn = $('#journalBtn');
  const elVizTip = $('#vizTip');
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
      if (state.view === 'insights') {
        // keep the dashboard as-is on background refreshes; only paint on first entry
        if (isInitial && !state.usage) loadUsage();
      } else if (elJournal && !elJournal.hidden) {
        renderJournal(); // refresh journal figures in place
      } else if (state.selectedId) {
        const s = state.sessions.find((x) => x.sessionId === state.selectedId);
        // On background refreshes leave the open detail untouched (preserve scroll,
        // in-progress brief, etc.); only (re)render on the initial load.
        if (s) { if (isInitial) renderDetail(s); }
        else showOverview();
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
    if (typeof updateJournalBtn === 'function') updateJournalBtn();
    if (state.deepMode) { elSkeleton.hidden = true; renderDeepResults(); return; }
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
    elJournal.hidden = true;
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
    elJournal.hidden = true;
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
        <div class="brief-card" id="briefCard">${briefCardHTML(s)}</div>
      </div>

      <div class="d-section">
        <div class="handoff-card" id="handoffCard">${handoffCardHTML(s)}</div>
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
        <div class="d-section-h">${icon('coins')} Usage &amp; est. cost</div>
        <div class="usage-card" id="usageCard">${usageCardHTML(s)}</div>
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
    $('#cmdCopy').addEventListener('click', (e) => copyText(s.resumeCommand, e.currentTarget));
    $('#copyCmdBtn').addEventListener('click', (e) => copyText(s.resumeCommand, e.currentTarget, 'Command copied'));
    $('#copyIdBtn').addEventListener('click', (e) => copyText(s.sessionId, e.currentTarget, 'Session ID copied'));
    $('#resumeBtn').addEventListener('click', () => resume(s.sessionId));
    $('#genSummaryBtn').addEventListener('click', () => genSummary(s.sessionId));
    wireBrief(s);
    wireHandoff(s);
    loadHandoff(s);
    loadUsageCard(s);
  }

  // ---- Pickup Brief card ----
  function briefStale(s) {
    if (!s.brief) return false;
    // stale if session has activity newer than when the brief was generated
    const gen = Date.parse(s.brief.generatedAt) || 0;
    const act = Date.parse(s.lastActivityAt) || 0;
    return act - gen > 60000; // >1 min newer
  }
  function briefCardHTML(s) {
    const hasBrief = s.brief && (s.brief.state || s.brief.nextPrompt);
    const head = `
      <div class="brief-head">
        <div class="brief-title"><span class="spark"><span>${icon('zap')}</span></span> Pickup Brief</div>
        <button class="btn btn-ghost" id="genBriefBtn" style="padding:6px 12px;font-size:12px">
          ${icon(hasBrief ? 'refresh' : 'zap')} ${hasBrief ? 'Regenerate' : 'Generate'}
        </button>
      </div>`;
    if (state.briefing[s.sessionId]) {
      return head + `<div class="sc-loading"><span class="spinner"></span><span>Reading the tail of this session with <b>claude&nbsp;·&nbsp;haiku</b><span class="sc-dots"><span></span><span></span><span></span></span></span></div>`;
    }
    if (!hasBrief) {
      const err = state.briefErr[s.sessionId];
      return head + (err
        ? `<div class="sc-error" style="margin-top:8px">${esc(err)}</div>`
        : `<div class="brief-empty">Generate a one-glance brief to get back into flow: where the work stands, what's still open, and a ready-to-paste prompt to continue.</div>`);
    }
    const b = s.brief;
    let html = head;
    if (briefStale(s)) {
      html += `<div class="brief-stale">${icon('clock')}<span>This session has newer activity since the brief was generated — regenerate to refresh.</span></div>`;
    }
    html += `<div class="brief-sec"><div class="brief-sec-h">State</div><div class="brief-state">${esc(b.state || '—')}</div></div>`;
    html += `<div class="brief-sec"><div class="brief-sec-h">Open threads</div>`;
    if (b.open && b.open.length) {
      html += `<div class="brief-open">${b.open.map((o) => `<div class="bo">${esc(o)}</div>`).join('')}</div>`;
    } else {
      html += `<div class="brief-open"><div class="bo-none">${icon('check')} Nothing left open — clean stopping point.</div></div>`;
    }
    html += `</div>`;
    if (b.nextPrompt) {
      html += `<div class="brief-sec"><div class="brief-sec-h">Next prompt</div>
        <div class="next-block">
          <div class="next-bar"><span class="nb-label">ready to paste</span>
            <button class="next-copy" id="nextCopy">${icon('copy')} Copy prompt</button></div>
          <div class="next-text" id="nextText">${esc(b.nextPrompt)}</div>
        </div></div>`;
    }
    html += `<div class="brief-meta">${icon('clock')}<span>Generated ${esc(relTime(b.generatedAt))}</span></div>`;
    return html;
  }
  function wireBrief(s) {
    const gen = $('#genBriefBtn'); if (gen) gen.addEventListener('click', () => genBrief(s.sessionId));
    const cp = $('#nextCopy'); if (cp && s.brief) cp.addEventListener('click', (e) => copyText(s.brief.nextPrompt, e.currentTarget, 'Prompt copied'));
  }
  async function genBrief(id) {
    if (state.briefing[id]) return;
    state.briefing[id] = true;
    state.briefErr[id] = null;
    const s = state.sessions.find((x) => x.sessionId === id);
    if (state.selectedId === id) { $('#briefCard').innerHTML = briefCardHTML(s); hydrateIcons($('#briefCard')); }
    status('Generating pickup brief via claude CLI…');
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(id) + '/brief', { method: 'POST' });
      const data = await r.json();
      state.briefing[id] = false;
      if (!r.ok) throw new Error(data.error || 'Brief failed');
      if (s) s.brief = { state: data.state, open: data.open || [], nextPrompt: data.nextPrompt, generatedAt: data.generatedAt, sessionLastActivity: data.sessionLastActivity };
      status('Pickup brief ready', 'ok');
      if (state.selectedId === id && s) { $('#briefCard').innerHTML = briefCardHTML(s); hydrateIcons($('#briefCard')); wireBrief(s); }
    } catch (e) {
      state.briefing[id] = false;
      state.briefErr[id] = e.message;
      status('Brief failed', 'err');
      if (state.selectedId === id && s) { $('#briefCard').innerHTML = briefCardHTML(s); hydrateIcons($('#briefCard')); wireBrief(s); }
    }
  }

  // ---- Handoff card ----
  function handoffStale(s, record) {
    const gen = Date.parse((record && record.generatedAt) || (s.handoff && s.handoff.generatedAt)) || 0;
    const act = Date.parse(s.lastActivityAt) || 0;
    return gen > 0 && act - gen > 60000; // >1 min newer
  }
  function handoffHead() {
    return `<div class="ho-head">
      <div class="ho-title"><span class="spark"><span>${icon('package')}</span></span> Handoff</div>
    </div>`;
  }
  function handoffCardHTML(s) {
    const id = s.sessionId;
    const head = handoffHead();

    if (state.handoffLoading[id]) {
      return head + `<div class="sc-loading"><span class="spinner"></span><span>Packaging this session with <b>claude&nbsp;·&nbsp;haiku</b><span class="sc-dots"><span></span><span></span><span></span></span></span></div>`;
    }

    const record = state.handoffs[id];
    if (!record) {
      // A server-side handoff exists but hasn't been fetched into the client yet.
      if (s.handoff) return head + `<div class="sc-loading"><span class="spinner"></span><span>Loading saved handoff…</span></div>`;
      const err = state.handoffErr[id];
      return head
        + (err ? `<div class="sc-error" style="margin-top:8px">${esc(err)}</div>` : '')
        + `<div class="ho-empty">Package this session's work so a fresh Claude Code session can pick it up — a dated <b>PROGRESS.md</b> entry, durable notes for <b>CLAUDE.md</b>, and a ready-to-paste kickstart prompt, written into the project directory.</div>
        <div class="ho-actions"><button class="btn btn-primary" id="hoPrepBtn">${icon('package')} Prepare Handoff</button></div>`;
    }

    // --- generated ---
    let html = head;
    const err = state.handoffErr[id];
    if (err) html += `<div class="sc-error" style="margin-top:8px">${esc(err)}</div>`;
    if (handoffStale(s, record)) {
      html += `<div class="brief-stale">${icon('clock')}<span>This session has newer activity since the handoff was generated — regenerate to refresh.</span></div>`;
    }

    const cwd = record.cwd;
    if (!cwd) {
      html += `<div class="sc-error" style="margin-top:12px">This session has no recorded project directory, so files can't be written.</div>`;
    } else {
      html += `<div class="ho-target">${icon('folder')}<span>Writes into <code>${esc(cwd)}</code></span></div>`;
      if (record.cwdExists === false) {
        html += `<div class="sc-error" style="margin-top:8px">That directory was not found on disk — regenerate from a session whose project still exists.</div>`;
      }
    }

    // PROGRESS.md preview
    html += `<div class="ho-sec">
      <div class="ho-sec-h"><span class="ho-fname">PROGRESS.md</span><span class="ho-flag">${record.progressMdExists ? 'inserts a new dated section' : 'creates the file'}</span></div>
      <pre class="ho-pre">${esc(record.progress || '—')}</pre>
    </div>`;

    // CLAUDE.md preview + toggle (only when durable knowledge exists)
    if (record.claudeSection) {
      const checked = state.includeClaudeMd[id];
      html += `<div class="ho-sec">
        <div class="ho-sec-h"><span class="ho-fname">CLAUDE.md</span><span class="ho-flag">${record.claudeMdExists ? 'appends a marked section' : 'creates the file'}</span></div>
        <pre class="ho-pre">${esc(record.claudeSection)}</pre>
        <label class="ho-check"><input type="checkbox" id="hoClaudeChk" ${checked ? 'checked' : ''} /><span>Also update CLAUDE.md</span></label>
        <div class="ho-check-note">appends a marked section — never overwrites your file</div>
      </div>`;
    }

    // KICKSTART — terminal-style copyable block (same styling as the brief's NEXT PROMPT)
    if (record.kickstart) {
      html += `<div class="ho-sec">
        <div class="ho-sec-h"><span class="ho-fname">Kickstart prompt</span></div>
        <div class="next-block">
          <div class="next-bar"><span class="nb-label">ready to paste</span>
            <button class="next-copy" id="hoKickCopy">${icon('copy')} Copy prompt</button></div>
          <div class="next-text" id="hoKickText">${esc(record.kickstart)}</div>
        </div>
      </div>`;
    }

    // written success
    const written = state.handoffWritten[id];
    if (written && written.length) {
      html += `<div class="ho-written">${icon('check')}<div class="ho-written-body">
        <div class="ho-written-h">Written to project</div>
        ${written.map((p) => `<div class="ho-path">${esc(p)}</div>`).join('')}
      </div></div>`;
    }

    const writing = state.handoffWriting[id];
    const canWrite = !!cwd && record.cwdExists !== false;
    html += `<div class="ho-actions">
      <button class="btn btn-primary" id="hoWriteBtn" ${(!canWrite || writing) ? 'disabled' : ''}>${writing ? '<span class="spinner" style="width:14px;height:14px;border-width:2px"></span> Writing…' : icon('download') + ' Write to Project'}</button>
      <button class="btn btn-ghost" id="hoRegenBtn">${icon('refresh')} Regenerate</button>
    </div>`;
    html += `<div class="brief-meta">${icon('clock')}<span>Generated ${esc(relTime(record.generatedAt))}</span></div>`;
    return html;
  }
  function rerenderHandoff(s) {
    if (!s || state.selectedId !== s.sessionId) return;
    const card = $('#handoffCard');
    if (card) { card.innerHTML = handoffCardHTML(s); hydrateIcons(card); wireHandoff(s); }
  }
  function wireHandoff(s) {
    const id = s.sessionId;
    const prep = $('#hoPrepBtn'); if (prep) prep.addEventListener('click', () => genHandoff(id));
    const regen = $('#hoRegenBtn'); if (regen) regen.addEventListener('click', () => genHandoff(id));
    const write = $('#hoWriteBtn'); if (write) write.addEventListener('click', () => writeHandoffFiles(id));
    const chk = $('#hoClaudeChk'); if (chk) chk.addEventListener('change', (e) => { state.includeClaudeMd[id] = e.target.checked; });
    const kc = $('#hoKickCopy'); const rec = state.handoffs[id];
    if (kc && rec) kc.addEventListener('click', (e) => copyText(rec.kickstart, e.currentTarget, 'Kickstart prompt copied'));
  }
  async function loadHandoff(s) {
    const id = s.sessionId;
    if (state.handoffs[id] || state.handoffLoading[id]) return; // already have it / generating
    if (!s.handoff) return; // nothing saved server-side
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(id) + '/handoff', { cache: 'no-store' });
      if (!r.ok) return;
      const data = await r.json();
      state.handoffs[id] = data;
      if (!(id in state.includeClaudeMd)) state.includeClaudeMd[id] = !data.claudeMdExists;
      rerenderHandoff(s);
    } catch (e) { /* leave placeholder */ }
  }
  async function genHandoff(id) {
    if (state.handoffLoading[id]) return;
    state.handoffLoading[id] = true;
    state.handoffErr[id] = null;
    state.handoffWritten[id] = null;
    const s = state.sessions.find((x) => x.sessionId === id);
    rerenderHandoff(s);
    status('Preparing handoff via claude CLI…');
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(id) + '/handoff', { method: 'POST' });
      const data = await r.json();
      state.handoffLoading[id] = false;
      if (!r.ok) throw new Error(data.error || 'Handoff failed');
      state.handoffs[id] = data;
      // checked by default ONLY when CLAUDE.md doesn't exist
      state.includeClaudeMd[id] = !data.claudeMdExists;
      if (s) s.handoff = { generatedAt: data.generatedAt, sessionLastActivity: data.sessionLastActivity, hasClaudeSection: !!data.claudeSection };
      status('Handoff ready', 'ok');
      rerenderHandoff(s);
    } catch (e) {
      state.handoffLoading[id] = false;
      state.handoffErr[id] = e.message;
      status('Handoff failed', 'err');
      rerenderHandoff(s);
    }
  }
  async function writeHandoffFiles(id) {
    if (state.handoffWriting[id]) return;
    const record = state.handoffs[id];
    if (!record) return;
    state.handoffWriting[id] = true;
    state.handoffErr[id] = null;
    const s = state.sessions.find((x) => x.sessionId === id);
    rerenderHandoff(s);
    const include = !!state.includeClaudeMd[id] && !!record.claudeSection;
    status('Writing handoff files…');
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(id) + '/handoff/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ includeClaudeMd: include }),
      });
      const data = await r.json();
      state.handoffWriting[id] = false;
      if (!r.ok) throw new Error(data.error || 'Write failed');
      state.handoffWritten[id] = data.written || [];
      // Files now exist on disk — reflect that in the preview flags.
      record.progressMdExists = true;
      if (include) record.claudeMdExists = true;
      status('Handoff written to project', 'ok');
      rerenderHandoff(s);
    } catch (e) {
      state.handoffWriting[id] = false;
      state.handoffErr[id] = e.message;
      status('Handoff write failed', 'err');
      rerenderHandoff(s);
    }
  }

  // ---- per-session Usage card ----
  function usageCardHTML(s) {
    const u = s.usage;
    if (!u || (!u.tokens.input && !u.tokens.output && !u.tokens.cacheRead && !u.tokens.cacheWrite)) {
      return '<div class="usage-empty">No usage recorded for this session.</div>';
    }
    const tk = u.tokens;
    const tokCell = (k, label, val) => `<div class="ut-cell">
      <div class="ut-top"><span class="ut-dot" style="background:${METRICS[k].hex}"></span><span class="ut-k">${label}</span></div>
      <div class="ut-v tnum">${esc(fmtTokens(val))}</div></div>`;
    const chips = state.usageDetail[s.sessionId];
    let chipHTML;
    if (chips) {
      chipHTML = chips.length
        ? `<div class="model-chips">${chips.map((m) => `<span class="mchip"><span class="mc-dot" style="background:${tierColor(m.model)}"></span>${esc(shortModel(m.model) || m.model)}<span class="mc-cost">${esc(fmtCost(m.cost))}</span></span>`).join('')}</div>`
        : '';
    } else {
      chipHTML = `<div class="model-chips" id="usageChips"><span class="mchip" style="opacity:.6">Loading models…</span></div>`;
    }
    return `
      <div class="usage-tokens">
        ${tokCell('input', 'Input', tk.input)}
        ${tokCell('output', 'Output', tk.output)}
        ${tokCell('cacheRead', 'Cache read', tk.cacheRead)}
        ${tokCell('cacheWrite', 'Cache write', tk.cacheWrite)}
      </div>
      <div class="usage-costrow">
        <div class="usage-cost"><span class="uc-num">${esc(fmtCost(u.cost))}</span><span class="uc-lbl">Est. cost (API-equivalent)</span></div>
        <div class="usage-time">${icon('timer')}${esc(fmtDuration(u.activeSeconds))} active</div>
      </div>
      ${chipHTML}`;
  }
  async function loadUsageCard(s) {
    if (state.usageDetail[s.sessionId]) return; // already have model chips
    try {
      const r = await fetch('/api/sessions/' + encodeURIComponent(s.sessionId) + '/usage', { cache: 'no-store' });
      const data = await r.json();
      state.usageDetail[s.sessionId] = data.byModel || [];
      if (state.selectedId === s.sessionId) {
        const card = $('#usageCard');
        if (card) { card.innerHTML = usageCardHTML(s); hydrateIcons(card); }
      }
    } catch (e) { /* leave placeholder */ }
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

  // =========================================================================
  // Chart tooltip (shared) — untrusted labels go in via textContent
  // =========================================================================
  function showTip(val, lbl, ev) {
    elVizTip.querySelector('.tip-val').textContent = val;
    const l = elVizTip.querySelector('.tip-lbl');
    l.textContent = lbl || '';
    l.hidden = !lbl;
    elVizTip.hidden = false;
    const pad = 12;
    let x = ev.clientX + 14, y = ev.clientY - 10;
    const w = elVizTip.offsetWidth, h = elVizTip.offsetHeight;
    if (x + w + pad > window.innerWidth) x = ev.clientX - w - 14;
    if (y + h + pad > window.innerHeight) y = window.innerHeight - h - pad;
    if (y < pad) y = pad;
    elVizTip.style.left = x + 'px';
    elVizTip.style.top = y + 'px';
  }
  function hideTip() { elVizTip.hidden = true; }

  // Delegate hover tooltips for any mark carrying data-tv (value) / data-tl (label).
  function wireTips(root) {
    root.addEventListener('pointermove', (e) => {
      const m = e.target.closest('[data-tv]');
      if (!m) { hideTip(); return; }
      showTip(m.getAttribute('data-tv'), m.getAttribute('data-tl'), e);
    });
    root.addEventListener('pointerleave', hideTip);
  }

  // =========================================================================
  // INSIGHTS dashboard
  // =========================================================================
  function rangeToParams() {
    const r = state.range;
    if (r.preset === 'all') return {};
    if (r.preset === 'custom') {
      const p = {};
      if (r.from) p.from = new Date(r.from + 'T00:00:00').toISOString();
      if (r.to) p.to = new Date(r.to + 'T23:59:59').toISOString();
      return p;
    }
    const days = r.preset === '7D' ? 7 : r.preset === '30D' ? 30 : 90;
    const from = new Date();
    from.setHours(0, 0, 0, 0);
    from.setDate(from.getDate() - (days - 1));
    return { from: from.toISOString(), to: new Date().toISOString() };
  }
  function rangeLabel() {
    const r = state.range;
    if (r.preset === '7D') return 'last 7 days';
    if (r.preset === '30D') return 'last 30 days';
    if (r.preset === '90D') return 'last 90 days';
    if (r.preset === 'all') return 'all time';
    if (r.from && r.to) return r.from + ' → ' + r.to;
    return 'custom range';
  }

  async function loadUsage() {
    state.usageLoading = true;
    const scroll = elInsights.querySelector('.insights');
    if (scroll) scroll.classList.add('ins-loading');
    else renderInsights(); // first paint shows skeleton frame
    try {
      const p = rangeToParams();
      const qs = new URLSearchParams(p).toString();
      const r = await fetch('/api/usage' + (qs ? '?' + qs : ''), { cache: 'no-store' });
      state.usage = await r.json();
      state.usageLoading = false;
      renderInsights();
    } catch (e) {
      state.usageLoading = false;
      console.error(e);
      elInsights.innerHTML = '<div class="insights"><div class="ins-empty">Could not load usage analytics.</div></div>';
    }
  }

  function renderInsights() {
    const u = state.usage;
    const presets = [['7D', '7D'], ['30D', '30D'], ['90D', '90D'], ['all', 'All']];
    const segBtns = presets.map(([k, lbl]) =>
      `<button data-range="${k}" aria-pressed="${state.range.preset === k}">${lbl}</button>`).join('');
    const cust = state.range;
    const head = `
      <div class="ins-head">
        <div>
          <h1>Insights</h1>
          <div class="ins-sub">Usage, time, and cost across your Claude Code sessions · <b>${esc(rangeLabel())}</b></div>
        </div>
        <div class="range-row" role="group" aria-label="Time range">
          <div class="segmented" id="rangeSeg">${segBtns}</div>
          <span class="range-custom">
            <input type="date" id="rangeFrom" value="${esc(cust.from || '')}" aria-label="From date" max="${todayStr()}" />
            <span>–</span>
            <input type="date" id="rangeTo" value="${esc(cust.to || '')}" aria-label="To date" max="${todayStr()}" />
          </span>
        </div>
      </div>`;

    if (!u || !u.daily) {
      elInsights.innerHTML = `<div class="insights">${head}<div class="ins-empty">Loading…</div></div>`;
      wireInsights();
      return;
    }
    if (!u.daily.length) {
      elInsights.innerHTML = `<div class="insights">${head}<div class="ins-empty">No usage recorded in this range. Try “All”.</div></div>`;
      wireInsights();
      return;
    }

    const t = u.totals;
    const sessionsActive = u.byProject.reduce((a, p) => a + p.sessions, 0);
    const stats = `
      <div class="ins-stats">
        <div class="ins-stat accent">
          <div class="is-lbl"><span class="is-ico">${icon('timer')}</span>Time spent</div>
          <div class="is-num">${esc(fmtDuration(t.activeSeconds))}</div>
          <div class="is-foot">${esc(rangeLabel())}</div>
        </div>
        <div class="ins-stat">
          <div class="is-lbl"><span class="is-ico">${icon('coins')}</span>Est. cost</div>
          <div class="is-num">${esc(fmtCost(t.cost))}</div>
          <div class="is-foot">API-equivalent</div>
        </div>
        <div class="ins-stat">
          <div class="is-lbl"><span class="is-ico">${icon('cpu')}</span>Tokens (in + out)</div>
          <div class="is-num">${esc(fmtTokens(t.tokens.input + t.tokens.output))}</div>
          <div class="is-foot">${esc(fmtTokens(t.tokens.cacheRead))} cache read</div>
        </div>
        <div class="ins-stat">
          <div class="is-lbl"><span class="is-ico">${icon('layers')}</span>Sessions active</div>
          <div class="is-num">${sessionsActive}</div>
          <div class="is-foot">${esc(rangeLabel())}</div>
        </div>
      </div>`;

    const charts = `
      <div class="viz-grid-2">
        <div class="viz-card wide">
          <div class="viz-card-h"><h3>Time spent per ${u.daily.length > 60 ? 'week' : 'day'}</h3><span class="vh-sub">hours active</span></div>
          ${timeBarChart(u.daily)}
        </div>
      </div>
      <div class="viz-grid-2">
        <div class="viz-card wide">
          <div class="viz-card-h">
            <h3>Tokens &amp; cost per day</h3>
            <div class="metric-seg" id="metricSeg">${Object.values(METRICS).map((m) =>
              `<button data-metric="${m.key}" aria-pressed="${state.metric === m.key}"><span class="ms-dot" style="background:${m.hex}"></span>${m.key === 'cost' ? 'Est. cost' : m.label.replace(' tokens', '')}</button>`).join('')}</div>
          </div>
          ${metricChart(u.daily, state.metric)}
        </div>
      </div>
      <div class="viz-grid-2">
        <div class="viz-card">
          <div class="viz-card-h"><h3>Model usage</h3><span class="vh-sub">est. cost</span></div>
          ${modelBars(u.byModel)}
        </div>
        <div class="viz-card">
          <div class="viz-card-h"><h3>Top projects by time</h3><span class="vh-sub">active hours</span></div>
          ${projectBars(u.byProject)}
        </div>
      </div>
      <div class="viz-grid-2">
        <div class="viz-card wide">
          <div class="viz-card-h"><h3>When you code</h3><span class="vh-sub">activity by hour of day (local)</span></div>
          ${hourHist(u.hourHistogram)}
        </div>
      </div>`;

    elInsights.innerHTML = `<div class="insights">${head}${stats}${charts}${insightCards(u.insights)}</div>`;
    wireInsights();
  }

  function todayStr() {
    const d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  // --- time-per-day / week bar chart (SVG) ---
  function timeBarChart(daily) {
    let rows = daily.map((d) => ({ label: d.date, sec: d.activeSeconds }));
    const weekly = daily.length > 60;
    if (weekly) {
      const map = new Map();
      for (const d of daily) {
        const wk = weekKey(d.date);
        map.set(wk, (map.get(wk) || 0) + d.activeSeconds);
      }
      rows = Array.from(map, ([label, sec]) => ({ label, sec }));
    }
    return svgBars(rows.map((r) => ({
      label: r.label,
      value: r.sec / 3600,
      tv: fmtDuration(r.sec),
      tl: prettyDate(r.label) + (weekly ? ' (week)' : ''),
    })), { unit: 'h', cls: 'time', fmtY: (v) => (v >= 10 ? v.toFixed(0) : v.toFixed(1)) });
  }

  // --- metric-switchable daily chart ---
  function metricChart(daily, metricKey) {
    const m = METRICS[metricKey];
    const rows = daily.map((d) => {
      const val = m.kind === 'cost' ? d.cost : d.tokens[m.key];
      return {
        label: d.date,
        value: val,
        tv: m.kind === 'cost' ? fmtCost(val) : fmtTokens(val),
        tl: prettyDate(d.date),
      };
    });
    return svgBars(rows, {
      color: m.color,
      fmtY: m.kind === 'cost' ? (v) => (v >= 1 ? '$' + Math.round(v) : '$' + v.toFixed(2)) : fmtTokens,
    });
  }

  // Generic SVG bar chart. opts: {color, cls, fmtY, unit}
  function svgBars(rows, opts) {
    opts = opts || {};
    const W = 900, H = 240, padL = 46, padR = 12, padT = 12, padB = 30;
    const iw = W - padL - padR, ih = H - padT - padB;
    const max = Math.max(1, ...rows.map((r) => r.value));
    const n = rows.length;
    const slot = iw / n;
    const bw = Math.min(24, Math.max(2, slot - 4));
    // y gridlines (4)
    const ticks = niceTicks(max, 4);
    let grid = '';
    for (const tk of ticks) {
      const y = padT + ih - (tk / max) * ih;
      grid += `<line class="grid-line" x1="${padL}" y1="${y.toFixed(1)}" x2="${W - padR}" y2="${y.toFixed(1)}"/>`;
      grid += `<text class="tick-txt tnum" x="${padL - 6}" y="${(y + 3).toFixed(1)}" text-anchor="end">${esc(opts.fmtY ? opts.fmtY(tk) : String(tk))}</text>`;
    }
    let bars = '';
    const labelEvery = Math.ceil(n / 12);
    rows.forEach((r, i) => {
      const x = padL + i * slot + (slot - bw) / 2;
      const h = (r.value / max) * ih;
      const y = padT + ih - h;
      const fill = opts.cls ? '' : ` style="fill:${opts.color || 'var(--viz-output)'}"`;
      const clsAttr = 'bar' + (opts.cls ? ' ' + opts.cls : '');
      bars += `<rect class="${clsAttr}"${fill} x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${bw.toFixed(1)}" height="${Math.max(0.5, h).toFixed(1)}" rx="3" data-tv="${esc(r.tv)}" data-tl="${esc(r.tl)}"/>`;
      if (i % labelEvery === 0) {
        bars += `<text class="bar-lbl" x="${(x + bw / 2).toFixed(1)}" y="${H - padB + 14}" text-anchor="middle">${esc(shortDate(r.label))}</text>`;
      }
    });
    const base = padT + ih;
    return `<svg class="viz-svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img">
      ${grid}
      <line class="axis-line" x1="${padL}" y1="${base}" x2="${W - padR}" y2="${base}"/>
      ${bars}
    </svg>`;
  }

  // --- model usage horizontal bars ---
  function modelBars(byModel) {
    if (!byModel.length) return '<div class="usage-empty">No model usage in range.</div>';
    const top = byModel.slice(0, 8);
    const max = Math.max(...top.map((m) => m.cost), 0.0001);
    const legend = uniqueTiers(top);
    const bars = top.map((m) => {
      const col = tierColor(m.model);
      const pct = Math.max(2, (m.cost / max) * 100);
      const tok = m.input + m.output + m.cacheRead + m.cacheWrite;
      return `<div class="mbar">
        <span class="mb-name" title="${esc(m.model)}"><span class="dot" style="background:${col}"></span>${esc(shortModel(m.model) || m.model)}</span>
        <span class="mb-track"><span class="mb-fill" style="width:${pct}%;background:${col}" data-tv="${esc(fmtCost(m.cost))}" data-tl="${esc(shortModel(m.model))} · ${esc(fmtTokens(tok))} tokens · ${m.count} msgs"></span></span>
        <span class="mb-val">${esc(fmtCost(m.cost))}<span class="mb-sub">${esc(fmtTokens(tok))}</span></span>
      </div>`;
    }).join('');
    return `<div class="mbars">${bars}</div>
      <div class="viz-legend">${legend.map((ti) => `<span class="lg"><span class="lg-key" style="background:${TIER_COLOR[ti]}"></span>${ti}</span>`).join('')}</div>`;
  }
  function uniqueTiers(models) {
    const set = [];
    for (const m of models) { const t = modelTier(m.model); if (set.indexOf(t) === -1) set.push(t); }
    return set;
  }

  // --- top projects by time ---
  function projectBars(byProject) {
    if (!byProject.length) return '<div class="usage-empty">No project activity in range.</div>';
    const top = byProject.slice(0, 8);
    const max = Math.max(...top.map((p) => p.activeSeconds), 1);
    const bars = top.map((p) => {
      const col = projColor(p.project);
      const pct = Math.max(2, (p.activeSeconds / max) * 100);
      return `<div class="mbar">
        <span class="mb-name" title="${esc(p.project)}"><span class="dot" style="background:${col};border-radius:50%"></span>${esc(p.project)}</span>
        <span class="mb-track"><span class="mb-fill" style="width:${pct}%;background:${col}" data-tv="${esc(fmtDuration(p.activeSeconds))}" data-tl="${esc(p.project)} · ${esc(fmtCost(p.cost))} · ${p.sessions} sessions"></span></span>
        <span class="mb-val">${esc(fmtDuration(p.activeSeconds))}<span class="mb-sub">${esc(fmtCost(p.cost))}</span></span>
      </div>`;
    }).join('');
    return `<div class="mbars">${bars}</div>`;
  }

  // --- hour-of-day histogram ---
  function hourHist(hours) {
    const max = Math.max(...hours, 1);
    const cols = hours.map((c, h) => {
      const pct = (c / max) * 100;
      return `<div class="hh-col" data-tv="${c} events" data-tl="${String(h).padStart(2, '0')}:00–${String(h).padStart(2, '0')}:59">
        <div class="hh-bar" style="height:${Math.max(2, pct)}%"></div></div>`;
    }).join('');
    const axis = hours.map((_, h) => (h % 3 === 0 ? `<div class="hh-tick">${h}</div>` : '<div class="hh-tick"></div>')).join('');
    return `<div class="hourhist">${cols}</div><div class="hh-axis">${axis}</div>`;
  }

  // --- efficiency insight cards ---
  function insightCards(ins) {
    if (!ins) return '';
    const hit = ins.cacheHitRate * 100;
    const hitStr = hit >= 99.95 ? '~100%' : hit.toFixed(1) + '%';
    const hitNote = hit >= 90 ? 'Excellent — prompt caching is saving you ' + fmtCost(ins.cacheSavings) + ' (API-equivalent).'
      : hit >= 60 ? 'Solid cache reuse. Longer, stable prompts cache better.'
        : 'Low reuse — shorter-lived context this range.';
    const mix = ins.modelMix || { tiers: {}, total: 0 };
    const mixEntries = Object.entries(mix.tiers).filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]);
    const topTier = mixEntries[0];
    const topPct = topTier && mix.total ? (topTier[1] / mix.total) * 100 : 0;
    const mixNote = mixEntries.map(([t, v]) => t + ' ' + Math.round((v / (mix.total || 1)) * 100) + '%').join(' · ')
      + (topPct > 80 ? ` — heavily on ${topTier[0]}, your priciest tier.` : '');
    const longest = ins.longestSession, exp = ins.mostExpensiveSession;

    const cards = [];
    cards.push(card('database', 'Cache hit rate', hitStr, hitNote));
    cards.push(card('gauge', 'Cost per active hour', fmtCost(ins.costPerActiveHour), 'What an hour of shipping costs in API-equivalent tokens.'));
    cards.push(card('cpu', 'Model mix', topTier ? Math.round(topPct) + '% ' + topTier[0] : '—', mixNote || 'No output tokens in range.'));
    if (longest || exp) {
      const parts = [];
      if (longest) parts.push(`<button class="ic-link" data-goto="${esc(longest.id)}">${esc(longest.title)}</button> — ${esc(fmtDuration(longest.seconds))}`);
      if (exp) parts.push(`<button class="ic-link" data-goto="${esc(exp.id)}">${esc(exp.title)}</button> — ${esc(fmtCost(exp.cost))}`);
      cards.push(`<div class="ins-card"><div class="ic-ico"><span>${icon('trophy')}</span></div><div>
        <div class="ic-title">Standout sessions</div>
        <div class="ic-note" style="margin-top:6px">Longest: ${parts[0] || '—'}<br>Most expensive: ${parts[1] || '—'}</div></div></div>`);
    }
    return `<div class="ins-cards">${cards.join('')}</div>`;
    function card(ic, title, big, note) {
      return `<div class="ins-card"><div class="ic-ico"><span>${icon(ic)}</span></div><div>
        <div class="ic-title">${esc(title)}</div><div class="ic-big">${esc(big)}</div><div class="ic-note">${esc(note)}</div></div></div>`;
    }
  }

  function wireInsights() {
    hydrateIcons(elInsights);
    wireTips(elInsights);
    const seg = $('#rangeSeg', elInsights);
    if (seg) seg.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      state.range.preset = b.dataset.range;
      loadUsage();
    });
    const ms = $('#metricSeg', elInsights);
    if (ms) ms.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      state.metric = b.dataset.metric;
      renderInsights(); // client-side, no refetch
    });
    ['rangeFrom', 'rangeTo'].forEach((id) => {
      const el = $('#' + id, elInsights);
      if (el) el.addEventListener('change', () => {
        state.range.from = $('#rangeFrom', elInsights).value || null;
        state.range.to = $('#rangeTo', elInsights).value || null;
        if (state.range.from && state.range.to) { state.range.preset = 'custom'; loadUsage(); }
      });
    });
    elInsights.querySelectorAll('.ic-link[data-goto]').forEach((b) =>
      b.addEventListener('click', () => { setView('sessions'); selectSession(b.dataset.goto); }));
  }

  // date helpers for charts
  function prettyDate(iso) {
    const d = new Date(iso + 'T00:00:00');
    if (isNaN(d)) return iso;
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  }
  function shortDate(iso) {
    const d = new Date(iso + 'T00:00:00');
    if (isNaN(d)) return iso;
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }
  function weekKey(iso) {
    const d = new Date(iso + 'T00:00:00');
    const day = (d.getDay() + 6) % 7; // Monday = 0
    d.setDate(d.getDate() - day);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function niceTicks(max, count) {
    const step = niceNum(max / count, true);
    const ticks = [];
    for (let v = step; v <= max + 1e-9; v += step) ticks.push(+v.toFixed(6));
    return ticks;
  }
  function niceNum(range, round) {
    const exp = Math.floor(Math.log10(range));
    const frac = range / Math.pow(10, exp);
    let nf;
    if (round) nf = frac < 1.5 ? 1 : frac < 3 ? 2 : frac < 7 ? 5 : 10;
    else nf = frac <= 1 ? 1 : frac <= 2 ? 2 : frac <= 5 ? 5 : 10;
    return nf * Math.pow(10, exp);
  }

  // =========================================================================
  // DEEP transcript search
  // =========================================================================
  function setDeepMode(on) {
    state.deepMode = on;
    $('.search-wrap').dataset.deep = String(on);
    elDeepToggle.setAttribute('aria-pressed', String(on));
    elSearch.placeholder = on ? 'Search inside conversations…  (min 3 chars)' : 'Search sessions…  ( / )';
    state.deepResults = null;
    if (on) {
      if (state.search.trim().length >= 3) runDeepSearch();
      else renderList();
    } else {
      renderList();
    }
  }
  let deepTimer = null;
  function scheduleDeepSearch() {
    clearTimeout(deepTimer);
    const q = state.search.trim();
    if (q.length < 3) { state.deepResults = null; state.deepLoading = false; renderList(); return; }
    state.deepLoading = true;
    renderList();
    deepTimer = setTimeout(runDeepSearch, 260);
  }
  async function runDeepSearch() {
    const q = state.search.trim();
    if (q.length < 3) return;
    const seq = ++state.deepSeq;
    state.deepLoading = true;
    try {
      const r = await fetch('/api/search?q=' + encodeURIComponent(q), { cache: 'no-store' });
      const data = await r.json();
      if (seq !== state.deepSeq) return; // superseded
      state.deepResults = data;
      state.deepLoading = false;
      renderList();
    } catch (e) {
      if (seq !== state.deepSeq) return;
      state.deepLoading = false;
      state.deepResults = { results: [], truncated: false };
      renderList();
    }
  }
  function highlight(text, q) {
    const out = esc(text);
    if (!q) return out;
    const idx = text.toLowerCase().indexOf(q.toLowerCase());
    if (idx === -1) return out;
    // rebuild with <mark> using escaped fragments
    let res = '';
    const lower = text.toLowerCase(), ql = q.toLowerCase();
    let i = 0;
    while (i < text.length) {
      const hit = lower.indexOf(ql, i);
      if (hit === -1) { res += esc(text.slice(i)); break; }
      res += esc(text.slice(i, hit)) + '<mark>' + esc(text.slice(hit, hit + q.length)) + '</mark>';
      i = hit + q.length;
    }
    return res;
  }
  function renderDeepResults() {
    const q = state.search.trim();
    elListContext.innerHTML = `<b>Deep search</b> · inside conversations`;
    if (state.deepLoading && !state.deepResults) {
      elSessionRows.hidden = true; elListEmpty.hidden = true;
      elSkeleton.hidden = false;
      elSkeleton.innerHTML = '<div class="deep-loading"><span class="spinner"></span>Scanning transcripts for “' + esc(q) + '”…</div>';
      return;
    }
    elSkeleton.hidden = true;
    const data = state.deepResults || { results: [] };
    if (!data.results.length) {
      elSessionRows.hidden = true;
      elListEmpty.hidden = false;
      elListEmpty.innerHTML = `<span class="empty-ico">${icon('scan')}</span>
        <div class="empty-title">No matches in conversations</div>
        <div class="empty-sub">Nothing containing “${esc(q)}” in any transcript body.</div>`;
      return;
    }
    // group by session, preserve order
    const groups = [];
    const map = new Map();
    for (const r of data.results) {
      let g = map.get(r.sessionId);
      if (!g) { g = { sessionId: r.sessionId, title: r.sessionTitle, project: r.projectName, hits: [] }; map.set(r.sessionId, g); groups.push(g); }
      g.hits.push(r);
    }
    elListEmpty.hidden = true;
    elSessionRows.hidden = false;
    const count = data.results.length;
    let html = `<div class="deep-head"><b>${count}${data.truncated ? '+' : ''}</b> match${count === 1 ? '' : 'es'} in <b>${groups.length}</b> session${groups.length === 1 ? '' : 's'}</div>`;
    for (const g of groups) {
      const col = projColor(g.project);
      html += `<div class="deep-group">
        <button class="deep-session" data-id="${esc(g.sessionId)}">
          <span class="dot" style="background:${col}"></span>
          <span class="ds-title">${esc(g.title)}</span>
          <span class="ds-proj">${esc(g.project)}</span>
          <span class="ds-count tnum">${g.hits.length}</span>
        </button>`;
      for (const h of g.hits) {
        html += `<button class="deep-hit" data-id="${esc(g.sessionId)}">
          <span class="dh-role ${h.role}">${h.role === 'user' ? 'You' : 'Claude'}</span>
          <span class="dh-snip">${highlight(h.snippet, q)}</span>
        </button>`;
      }
      html += `</div>`;
    }
    elSessionRows.innerHTML = html;
  }

  // =========================================================================
  // PROJECT JOURNAL
  // =========================================================================
  function openJournal(project) {
    state.journalProject = project;
    setView('sessions');
    hideDetailPanes();
    elJournal.hidden = false;
    app.dataset.detailOpen = 'true';
    renderJournal();
    elJournal.parentElement.scrollTop = 0;
  }
  function journalEntries(project) {
    return state.sessions
      .filter((s) => (s.projectName || s.projectKey) === project)
      .slice()
      .sort((a, b) => (Date.parse(a.createdAt || a.lastActivityAt) || 0) - (Date.parse(b.createdAt || b.lastActivityAt) || 0));
  }
  function renderJournal() {
    const project = state.journalProject;
    const entries = journalEntries(project);
    const col = projColor(project);
    const totalCost = entries.reduce((a, s) => a + (s.usage ? s.usage.cost : 0), 0);
    const totalSec = entries.reduce((a, s) => a + (s.usage ? s.usage.activeSeconds : 0), 0);

    let body = '';
    let curMonth = '';
    for (const s of entries) {
      const d = new Date(s.createdAt || s.lastActivityAt);
      const monthKey = isNaN(d) ? 'Undated' : d.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
      if (monthKey !== curMonth) { curMonth = monthKey; body += `<div class="jr-month">${esc(monthKey)}</div>`; }
      body += journalEntryHTML(s);
    }

    elJournal.innerHTML = `
      <div class="jr-head">
        <div>
          <h1 class="jr-title"><span class="dot" style="background:${col}"></span>${esc(project)}</h1>
          <div class="jr-sub">${entries.length} session${entries.length === 1 ? '' : 's'} · ${esc(fmtDuration(totalSec))} active · ${esc(fmtCost(totalCost))} est.</div>
        </div>
        <div class="jr-actions">
          <button class="jr-back" id="journalBack">${icon('arrowLeft')} Back</button>
          <button class="btn btn-ghost" id="journalCopy">${icon('copy')} Copy Markdown</button>
          <button class="btn btn-primary" id="journalDownload">${icon('download')} Download Markdown</button>
        </div>
      </div>
      ${entries.length ? body : '<div class="ins-empty">No sessions in this project yet.</div>'}`;
    hydrateIcons(elJournal);
    $('#journalBack').addEventListener('click', () => { hideDetailPanes(); showOverview(); });
    $('#journalCopy').addEventListener('click', (e) => copyText(buildJournalMarkdown(project, entries), e.currentTarget, 'Journal copied'));
    $('#journalDownload').addEventListener('click', () => downloadMarkdown(project, entries));
    elJournal.querySelectorAll('.je-title, .je-open').forEach((el) =>
      el.addEventListener('click', () => { hideDetailPanes(); selectSession(el.dataset.id); }));
  }
  function journalEntryHTML(s) {
    const d = new Date(s.createdAt || s.lastActivityAt);
    const dateStr = isNaN(d) ? '' : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) + ' · ' + d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    const dur = s.usage ? fmtDuration(s.usage.activeSeconds) : null;
    const cost = s.usage ? fmtCost(s.usage.cost) : null;
    const pills = [];
    if (dur) pills.push(`<span class="je-pill">${icon('clock')}${esc(dur)}</span>`);
    pills.push(`<span class="je-pill">${icon('message')}${s.userMessageCount} prompts</span>`);
    if (cost) pills.push(`<span class="je-pill">${esc(cost)}</span>`);
    if (s.customTitle) pills.push('<span class="je-pill named">Named</span>');
    const body = summaryLead(s) || s.firstPrompt || 'No summary or prompt captured.';
    return `<div class="jr-entry">
      <div class="je-date tnum">${esc(dateStr)}</div>
      <div class="je-title" data-id="${esc(s.sessionId)}">${esc(s.title)}</div>
      <div class="jr-pills">${pills.join('')}</div>
      <div class="je-body">${esc(body)}</div>
    </div>`;
  }
  function buildJournalMarkdown(project, entries) {
    let md = '# ' + project + ' — Claude Code Journal\n\n';
    for (const s of entries) {
      const d = new Date(s.createdAt || s.lastActivityAt);
      const date = isNaN(d) ? '(undated)' : d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
      const bits = [];
      if (s.usage) bits.push(fmtDuration(s.usage.activeSeconds));
      bits.push(s.userMessageCount + ' prompts');
      if (s.usage) bits.push('~' + fmtCost(s.usage.cost));
      md += '## ' + date + ' — ' + s.title + ' (' + bits.join(', ') + ')\n';
      const body = (s.summary && s.summary.text) ? s.summary.text : (s.firstPrompt || '');
      if (body) md += body.trim() + '\n';
      md += '\n';
    }
    return md;
  }
  function downloadMarkdown(project, entries) {
    const md = buildJournalMarkdown(project, entries);
    const blob = new Blob([md], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = project.replace(/[^A-Za-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') + '-journal.md';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    status('Journal downloaded', 'ok');
  }

  // =========================================================================
  // View management
  // =========================================================================
  function hideDetailPanes() { elOverview.hidden = true; elDetail.hidden = true; elJournal.hidden = true; }
  function setView(view) {
    state.view = view;
    app.dataset.view = view;
    elInsights.hidden = view !== 'insights';
    if (view === 'insights') {
      $$('.nav-item[data-filter]').forEach((n) => (n.dataset.active = 'false'));
      $$('.project-item').forEach((n) => (n.dataset.active = 'false'));
      if (!state.usage) loadUsage(); else { renderInsights(); loadUsage(); }
    }
  }

  // ---- filters / nav ----
  function setFilter(filter, project) {
    state.view = 'sessions';
    app.dataset.view = 'sessions';
    elInsights.hidden = true;
    state.filter = filter;
    state.project = project || null;
    $$('.nav-item[data-filter]').forEach((n) => (n.dataset.active = String(n.dataset.filter === filter && filter !== 'project')));
    updateJournalBtn();
    renderSidebar();
    renderList();
  }
  function updateJournalBtn() {
    const show = state.filter === 'project' && !!state.project;
    elJournalBtn.hidden = !show;
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
    if (state.deepMode) return; // deep-search list isn't arrow-navigable
    const list = currentList();
    if (!list.length) return;
    let idx = list.findIndex((s) => s.sessionId === state.selectedId);
    idx = idx === -1 ? (dir > 0 ? 0 : list.length - 1) : idx + dir;
    idx = Math.max(0, Math.min(list.length - 1, idx));
    selectSession(list[idx].sessionId, { scroll: true });
  }

  // ---- events ----
  function bind() {
    $$('.nav-item[data-filter]').forEach((n) => n.addEventListener('click', () => setFilter(n.dataset.filter)));
    $('.nav-insights').addEventListener('click', () => setView('insights'));
    elProjectList.addEventListener('click', (e) => {
      const b = e.target.closest('.project-item'); if (b) setFilter('project', b.dataset.proj);
    });
    elSessionRows.addEventListener('click', (e) => {
      const b = e.target.closest('[data-id]'); if (b) selectSession(b.dataset.id);
    });
    elOverview.addEventListener('click', (e) => {
      const rec = e.target.closest('.recent-item'); if (rec) { selectSession(rec.dataset.id); return; }
      const bar = e.target.closest('.bar-row'); if (bar) setFilter('project', bar.dataset.proj);
    });

    elDeepToggle.addEventListener('click', () => setDeepMode(!state.deepMode));
    elJournalBtn.addEventListener('click', () => { if (state.project) openJournal(state.project); });

    elSearch.addEventListener('input', () => {
      state.search = elSearch.value;
      elSearchClear.hidden = !elSearch.value;
      if (state.deepMode) scheduleDeepSearch();
      else renderList();
    });
    elSearchClear.addEventListener('click', () => {
      elSearch.value = ''; state.search = ''; elSearchClear.hidden = true;
      state.deepResults = null;
      renderList(); elSearch.focus();
    });

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
        if (state.deepMode && (state.search || document.activeElement === elSearch)) { setDeepMode(false); elSearch.blur(); return; }
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
