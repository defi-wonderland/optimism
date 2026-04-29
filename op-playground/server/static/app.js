(function() {
  'use strict';

  // ────────────────────────────────────────────────────────────────────────
  // State + utilities
  // ────────────────────────────────────────────────────────────────────────

  const startTime = Date.now();
  const state = {
    snapshot: null,           // /api/state
    chains: [],               // /api/chains
    eventLog: [],             // capped to 500
    eventListeners: [],       // live SSE consumers
  };

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

  function escapeHTML(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function fmtNum(n) { return n != null ? n.toLocaleString() : '—'; }
  function shortHash(h, n) {
    if (!h) return '—';
    n = n || 10;
    return h.slice(0, n) + '…';
  }
  function shortAddr(a) {
    if (!a || a === '0x0000000000000000000000000000000000000000') return '—';
    return a.slice(0, 6) + '…' + a.slice(-4);
  }
  function uptimeStr() {
    const s = Math.floor((Date.now() - startTime) / 1000);
    if (s < 60) return s + 's';
    const m = Math.floor(s / 60);
    if (m < 60) return m + 'm ' + (s % 60) + 's';
    return Math.floor(m / 60) + 'h ' + (m % 60) + 'm';
  }
  function fmtTimeAgo(ts) {
    if (!ts) return '—';
    const ms = Date.now() - ts * 1000;
    if (ms < 0) return new Date(ts * 1000).toLocaleTimeString();
    const s = Math.floor(ms / 1000);
    if (s < 60) return s + 's ago';
    const m = Math.floor(s / 60);
    if (m < 60) return m + 'm ago';
    const h = Math.floor(m / 60);
    if (h < 24) return h + 'h ago';
    return Math.floor(h / 24) + 'd ago';
  }
  function copyText(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).catch(() => {});
  }

  // ────────────────────────────────────────────────────────────────────────
  // Router
  // ────────────────────────────────────────────────────────────────────────

  const routes = []; // [{ pattern: RegExp, names: [], handler: fn }]
  function route(path, handler) {
    const names = [];
    const pattern = new RegExp('^' + path.replace(/:(\w+)/g, (_, n) => { names.push(n); return '([^/]+)'; }) + '/?$');
    routes.push({ pattern, names, handler });
  }
  function navigate(path) { location.hash = '#' + path; }
  function currentPath() {
    let h = location.hash || '#/';
    if (h[0] === '#') h = h.slice(1);
    if (!h.startsWith('/')) h = '/' + h;
    return h;
  }
  function dispatch() {
    const path = currentPath();
    for (const link of $$('.nav-link')) {
      const r = link.getAttribute('data-route');
      const isActive = path === r || (r !== '/' && path.startsWith(r + '/')) || (r !== '/' && path === r);
      link.classList.toggle('active', isActive);
    }
    const view = $('#view');
    for (const r of routes) {
      const m = path.match(r.pattern);
      if (!m) continue;
      const params = {};
      r.names.forEach((n, i) => { params[n] = decodeURIComponent(m[i + 1]); });
      view.innerHTML = '';
      try {
        r.handler(view, params);
      } catch (e) {
        view.innerHTML = '<div class="empty">Render error: ' + escapeHTML(e.message) + '</div>';
        console.error(e);
      }
      return;
    }
    view.innerHTML = '<div class="empty">Not found: ' + escapeHTML(path) + '</div>';
  }
  window.addEventListener('hashchange', dispatch);

  // ────────────────────────────────────────────────────────────────────────
  // Topbar + nav footer (live)
  // ────────────────────────────────────────────────────────────────────────

  function setCrumbs(parts) {
    const html = parts.map((p, i) => {
      if (typeof p === 'string') return '<span>' + escapeHTML(p) + '</span>';
      return '<a href="#' + p.href + '">' + escapeHTML(p.label) + '</a>';
    }).join('<span class="crumb-sep">/</span>');
    $('#topbar-title').innerHTML = html;
  }

  function tickHeader() {
    if (state.snapshot) $('#nav-mode').textContent = state.snapshot.mode + ' mode';
    $('#nav-uptime').textContent = 'up ' + uptimeStr();

    // Sequencer drift: largest L2-unsafe-vs-L1-origin gap across L2s.
    const drift = $('#topbar-drift');
    if (drift && state.snapshot && state.snapshot.l2s) {
      const items = [];
      for (const [name, l2] of Object.entries(state.snapshot.l2s)) {
        if (!l2.unsafe || !l2.current_l1) continue;
        const lag = state.snapshot.l1.head.number - l2.current_l1.number;
        items.push({ name, lag, unsafe: l2.unsafe.number, l1Origin: l2.current_l1.number });
      }
      if (items.length === 0) {
        drift.textContent = '';
        drift.className = '';
      } else {
        const maxLag = items.reduce((acc, it) => it.lag > acc.lag ? it : acc, items[0]);
        drift.textContent = `${maxLag.name} L1-origin lag: ${maxLag.lag} block${maxLag.lag === 1 ? '' : 's'}`;
        drift.className = maxLag.lag > 20 ? 'danger' : maxLag.lag > 5 ? 'warning' : '';
      }
    }
  }
  setInterval(tickHeader, 1000);

  $$('#topbar-actions button[data-advance]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const seconds = btn.getAttribute('data-advance');
      try {
        const r = await fetch('/api/control/advance-time?seconds=' + seconds, { method: 'POST' });
        const body = await r.json();
        if (body.error) alert(body.error);
      } catch (e) { alert('Request failed: ' + e.message); }
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Background polling: snapshot + chains list (shared across views)
  // ────────────────────────────────────────────────────────────────────────

  async function pollSnapshot() {
    try {
      const r = await fetch('/api/state');
      if (r.ok) state.snapshot = await r.json();
    } catch (e) {}
  }
  async function loadChains() {
    try {
      const r = await fetch('/api/chains');
      if (r.ok) state.chains = await r.json();
    } catch (e) {}
  }
  setInterval(pollSnapshot, 1000);

  // SSE pipeline — single connection, fans out to view-registered listeners.
  function setupSSE() {
    const evtSource = new EventSource('/api/events');
    function emit(evt) {
      state.eventLog.unshift(evt);
      if (state.eventLog.length > 500) state.eventLog.pop();
      state.eventListeners.forEach(fn => { try { fn(evt); } catch (e) {} });
    }
    evtSource.onmessage = e => { try { emit(JSON.parse(e.data)); } catch (ex) {} };
    ['l1.block', 'l2.block', 'control.sequencer.start', 'control.sequencer.stop',
     'control.batcher.start', 'control.batcher.stop', 'script.start', 'script.done', 'script.error'
    ].forEach(type => {
      evtSource.addEventListener(type, e => emit({ type, time: new Date().toISOString(), data: e.data }));
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Home (chain cards)
  // ────────────────────────────────────────────────────────────────────────

  route('/', (view) => {
    setCrumbs(['Home']);
    view.innerHTML = `
      <div class="page-head">
        <h1>Chains <small>L1 + L2 status at a glance</small></h1>
      </div>
      <div id="chains" class="chains-grid"></div>`;
    renderHome();
    const t = setInterval(() => { if (currentPath() !== '/') return clearInterval(t); renderHome(); }, 1000);
  });

  function renderHome() {
    const s = state.snapshot;
    const grid = $('#chains');
    if (!grid) return;
    if (!s) { grid.innerHTML = '<div class="empty"><span class="spinner"></span> connecting…</div>'; return; }

    let html = '';

    // L1 card
    html += chainCardHTML({
      kind: 'l1',
      name: 'L1',
      sub: 'fake-pos',
      rows: [
        ['Head', fmtNum(s.l1.head.number) + ' <code>' + shortHash(s.l1.head.hash) + '</code>'],
        ['Finalized', fmtNum(s.l1.finalized.number)],
      ],
    });

    // L2 cards
    for (const [name, l2] of Object.entries(s.l2s || {})) {
      html += chainCardHTML({
        kind: 'l2',
        name,
        sub: 'chain ' + l2.chain_id,
        rows: [
          ['Unsafe', fmtNum(l2.unsafe.number) + ' <code>' + shortHash(l2.unsafe.hash) + '</code>'],
          ['Cross-unsafe', fmtNum(l2.cross_unsafe.number)],
          ['Local-safe', fmtNum(l2.local_safe.number)],
          ['Safe', fmtNum(l2.safe.number)],
          ['Finalized', fmtNum(l2.finalized.number)],
          ['L1 origin', fmtNum(l2.current_l1.number)],
          ['Sequencer', '<span class="' + (l2.sequencer_active ? 'status-on' : 'status-off') + '">' + (l2.sequencer_active ? 'RUNNING' : 'STOPPED') + '</span>'],
          ['Batcher', '<span class="' + (l2.batcher_running ? 'status-on' : 'status-off') + '">' + (l2.batcher_running ? 'RUNNING' : 'STOPPED') + '</span>'],
        ],
        controls: [
          { label: 'Start seq', cls: 'btn success', cmd: ['sequencer', name, 'start'] },
          { label: 'Stop seq', cls: 'btn danger', cmd: ['sequencer', name, 'stop'] },
          { label: 'Step', cls: 'btn', cmd: ['sequencer', name, 'step'] },
          { label: 'Start batch', cls: 'btn success', cmd: ['batcher', name, 'start'] },
          { label: 'Stop batch', cls: 'btn danger', cmd: ['batcher', name, 'stop'] },
        ],
      });
    }

    grid.innerHTML = html;
    grid.querySelectorAll('button[data-cmd]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const [comp, chain, action] = btn.getAttribute('data-cmd').split(',');
        try {
          const r = await fetch('/api/control/' + comp + '/' + chain + '/' + action, { method: 'POST' });
          const body = await r.json();
          if (body.error) alert(body.error);
        } catch (e) { alert('Request failed: ' + e.message); }
      });
    });
  }

  function chainCardHTML(c) {
    const rows = c.rows.map(r => '<tr><td>' + escapeHTML(r[0]) + '</td><td>' + r[1] + '</td></tr>').join('');
    const ctrls = (c.controls || []).map(b =>
      '<button class="' + b.cls + '" data-cmd="' + b.cmd.join(',') + '">' + escapeHTML(b.label) + '</button>'
    ).join('');
    return `
      <section class="chain-card">
        <h2>${escapeHTML(c.name)}</h2>
        <div class="chain-id">${escapeHTML(c.sub)}</div>
        <table class="kv">${rows}</table>
        ${ctrls ? '<div class="controls">' + ctrls + '</div>' : ''}
      </section>`;
  }

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Tools (list + detail)
  // ────────────────────────────────────────────────────────────────────────

  route('/tools', async (view) => {
    setCrumbs(['Tools']);
    view.innerHTML = `
      <div class="page-head"><h1>Tools <small>scripts that read or mutate the chain</small></h1></div>
      <p class="page-sub">Each tool is a runnable shell script bundled with the playground. Click a card to see what it does, what L1/L2 calls it'll make, and run it. Output is captured and shown inline.</p>
      <div id="tools-list"><div class="empty"><span class="spinner"></span> loading…</div></div>`;
    try {
      const r = await fetch('/api/scripts');
      const tools = (r.ok ? await r.json() : []) || [];
      const list = $('#tools-list');
      if (tools.length === 0) { list.innerHTML = '<div class="empty">No tools registered.</div>'; return; }
      // Group by family.
      const groups = {};
      for (const t of tools) {
        const fam = t.family || 'misc';
        (groups[fam] = groups[fam] || []).push(t);
      }
      const familyOrder = ['consensus-upgrade', 'diagnostics', 'bridging', 'misc'];
      const orderedFams = Object.keys(groups).sort((a, b) => {
        const ia = familyOrder.indexOf(a); const ib = familyOrder.indexOf(b);
        return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
      });
      list.innerHTML = orderedFams.map(fam => `
        <h3 style="font-size:11px;color:var(--text-1);text-transform:uppercase;letter-spacing:0.5px;margin:18px 0 8px">${escapeHTML(fam.replace(/-/g, ' '))}</h3>
        <div class="tools-grid">
          ${groups[fam].map(t => `
            <a class="tool-card" href="#/tools/${encodeURIComponent(t.name)}">
              <h3>${escapeHTML(t.title || humanize(t.name))}</h3>
              <p>${escapeHTML(t.description || '(no description)')}</p>
            </a>`).join('')}
        </div>`).join('');
    } catch (e) {
      $('#tools-list').innerHTML = '<div class="empty">Failed to load: ' + escapeHTML(e.message) + '</div>';
    }
  });

  route('/tools/:name', async (view, params) => {
    const name = params.name;
    setCrumbs([{ label: 'Tools', href: '/tools' }, humanize(name)]);
    view.innerHTML = `
      <div class="page-head"><h1>${escapeHTML(humanize(name))}</h1></div>
      <div id="tool-body"><div class="empty"><span class="spinner"></span> loading…</div></div>`;

    let detail;
    try {
      const r = await fetch('/api/scripts/' + encodeURIComponent(name));
      if (!r.ok) throw new Error('HTTP ' + r.status);
      detail = await r.json();
    } catch (e) {
      $('#tool-body').innerHTML = '<div class="empty">Failed to load: ' + escapeHTML(e.message) + '</div>';
      return;
    }

    const meta = detail.meta || {};
    const argsHint = meta.usage_example || scriptArgsHint(detail.source);

    // Re-set the title using the meta if available.
    if (meta.title || detail.title) {
      $('.page-head h1').textContent = meta.title || detail.title;
      setCrumbs([{ label: 'Tools', href: '/tools' }, meta.title || detail.title]);
    }

    $('#tool-body').innerHTML = `
      <div class="card">
        <p class="page-sub" style="margin: 0 0 8px">${escapeHTML(meta.summary || detail.description || '(no description)')}</p>
        ${meta.audience ? `<div class="dim small">For: ${escapeHTML(meta.audience)}</div>` : ''}
      </div>

      ${meta.description ? `<div class="card"><h2>What it does</h2><div class="tool-md">${renderMarkdown(meta.description)}</div></div>` : ''}

      ${(meta.prerequisites || []).length ? `<div class="card"><h2>Prerequisites</h2>${renderItems(meta.prerequisites)}</div>` : ''}

      ${(meta.calls || []).length ? `<div class="card"><h2>Calls it will make</h2>${renderCalls(meta.calls)}</div>` : ''}

      ${(meta.inputs || []).length ? `<div class="card"><h2>Inputs</h2>${renderItems(meta.inputs)}</div>` : ''}

      <div class="card">
        <h2>Run
          <span id="tool-status" class="tool-status"><span class="dot"></span><span class="label">idle</span></span>
        </h2>
        ${argsHint ? `<input id="tool-args" type="text" placeholder="${escapeHTML(argsHint)}" style="width:100%; padding: 6px 10px; background: var(--bg-0); border: 1px solid var(--border); border-radius: 4px; color: var(--text-0); font-family: inherit; font-size: 12px; margin-bottom: 10px"/>` : ''}
        <div>
          <button class="btn primary" id="tool-run">Run</button>
        </div>
        <div id="tool-results" class="tool-results"></div>
        <pre id="tool-output" class="tool-output" style="display:none"></pre>
      </div>

      ${(meta.produces || []).length ? `<div class="card"><h2>Produces (when successful)</h2>${renderItems(meta.produces)}</div>` : ''}

      <details class="collapsible" style="margin-top: 16px">
        <summary>View script source (${detail.source.split('\n').length} lines)</summary>
        <pre class="tool-detail-source" style="margin-top: 8px">${highlightShell(detail.source)}</pre>
      </details>`;

    $('#tool-run').addEventListener('click', () => runTool(name, meta));
  });

  function renderItems(items) {
    return '<ul class="tool-items">' + items.map(it =>
      `<li><strong>${escapeHTML(it.title || '')}</strong>${it.detail ? ' — <span class="muted">' + escapeHTML(it.detail) + '</span>' : ''}</li>`
    ).join('') + '</ul>';
  }
  function renderCalls(calls) {
    return '<ol class="tool-calls">' + calls.map(c => `
      <li>
        <span class="tool-call-actor">${escapeHTML(c.actor || '?')}</span>
        <span class="tool-call-arrow">→</span>
        <span class="tool-call-target">${escapeHTML(c.target || '?')}</span>
        <code class="tool-call-method">${escapeHTML(c.method || '')}</code>
        ${c.note ? `<div class="tool-call-note muted small">${escapeHTML(c.note)}</div>` : ''}
      </li>`).join('') + '</ol>';
  }
  function renderMarkdown(src) {
    // Tiny markdown subset: headings, bold, inline code, paragraphs, bullets.
    const blocks = String(src).split(/\n\n+/);
    return blocks.map(block => {
      const lines = block.split('\n');
      if (/^##\s/.test(block)) return `<h3>${escapeMD(block.replace(/^##\s+/, ''))}</h3>`;
      if (/^#\s/.test(block)) return `<h2>${escapeMD(block.replace(/^#\s+/, ''))}</h2>`;
      if (lines.every(l => /^[-*]\s/.test(l))) {
        return '<ul>' + lines.map(l => `<li>${escapeMD(l.replace(/^[-*]\s+/, ''))}</li>`).join('') + '</ul>';
      }
      return `<p>${escapeMD(block.replace(/\n/g, ' '))}</p>`;
    }).join('');
  }
  function escapeMD(s) {
    return escapeHTML(s)
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  }

  function humanize(slug) {
    return slug.replace(/[-_]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  }

  function scriptRequirements(source) {
    // Pull the "Requires: ..." comment line for env-var hints.
    const m = source.match(/^#\s*Requires:\s*(.+)$/m);
    if (!m) return '';
    const items = m[1].split(/[,;]+/).map(s => s.trim()).filter(Boolean);
    return '<table class="kv">' + items.map(it => `<tr><td>env</td><td><code>${escapeHTML(it)}</code></td></tr>`).join('') + '</table>';
  }
  function scriptArgsHint(source) {
    // Heuristic: if the source uses ${1}, ${2}, etc., show hint from "Usage:" line.
    if (!/\$\{?[1-9]\}?/.test(source)) return null;
    const m = source.match(/^#\s*Usage:\s*(.+)$/m) || source.match(/^#\s*[\w-]+\.sh:\s*(.+)$/m);
    return m ? m[1] : 'arg1 arg2 …';
  }
  function highlightShell(src) {
    // Lightweight syntax highlighting — comments, strings, $vars, common keywords.
    return escapeHTML(src)
      .replace(/(^|\n)([ \t]*#[^\n]*)/g, (_, p, c) => p + '<span class="sh-comment">' + c + '</span>')
      .replace(/(&quot;[^&\n]*?&quot;|&#39;[^&\n]*?&#39;)/g, '<span class="sh-string">$1</span>')
      .replace(/(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)/g, '<span class="sh-var">$1</span>')
      .replace(/\b(set|if|then|else|fi|for|do|done|while|case|esac|function|export|local|return|exit|cd|echo)\b/g, '<span class="sh-keyword">$1</span>');
  }

  async function runTool(name, meta) {
    const out = $('#tool-output');
    const results = $('#tool-results');
    const argsInput = $('#tool-args');
    out.style.display = 'block';
    out.textContent = '';
    results.innerHTML = '';
    setStatus('running', 'running…');
    $('#tool-run').disabled = true;

    const txs = new Set();
    const addrs = new Map();
    const snapshots = (meta && meta.snapshots) || [];
    let stateDiff = null;

    // Capture state before the run so we can render a diff after.
    const before = await captureSnapshots(snapshots);

    function addLine(line) {
      out.textContent += line + '\n';
      out.scrollTop = out.scrollHeight;
      // Pull tx hashes + deployed addresses from forge/cast output.
      const txMatch = line.match(/0x[0-9a-fA-F]{64}/g);
      if (txMatch) txMatch.forEach(h => txs.add(h));
      const dep = line.match(/Deployed (\w+)\s*[:=]?\s*(0x[0-9a-fA-F]{40})/i);
      if (dep) addrs.set(dep[1], dep[2]);
      renderResults();
    }
    function renderResults() {
      let html = '';
      if (stateDiff) html += stateDiff;
      if (addrs.size) {
        html += '<div class="tool-result-row"><span class="label">deployed</span><span>' +
          Array.from(addrs.entries()).map(([k, v]) => `<code>${escapeHTML(k)}</code> <a href="#/explorer/L1/address/${escapeHTML(v)}"><code>${escapeHTML(v)}</code></a>`).join(' &nbsp; ') +
          '</span></div>';
      }
      if (txs.size) {
        html += '<div class="tool-result-row"><span class="label">transactions</span><span>' +
          Array.from(txs).map(h => `<a href="#/explorer/L1/tx/${escapeHTML(h)}"><code>${shortHash(h, 12)}</code></a>`).join(' &nbsp; ') +
          '</span></div>';
      }
      results.innerHTML = html;
    }

    async function finishWithDiff() {
      if (snapshots.length === 0) return;
      const after = await captureSnapshots(snapshots);
      stateDiff = renderSnapshotDiff(snapshots, before, after);
      renderResults();
    }

    try {
      const argsParam = argsInput && argsInput.value ? '?args=' + encodeURIComponent(argsInput.value) : '';
      const r = await fetch('/api/scripts/' + encodeURIComponent(name) + '/run' + argsParam, { method: 'POST' });
      const body = await r.json();
      if (body.error) { setStatus('failed', body.error); $('#tool-run').disabled = false; return; }
      const es = new EventSource('/api/scripts/runs/' + body.run_id + '/stream');
      es.onmessage = e => addLine(e.data);
      es.addEventListener('done', async () => {
        es.close();
        setStatus('done', 'done');
        $('#tool-run').disabled = false;
        await finishWithDiff();
      });
      es.onerror = async () => {
        es.close();
        setStatus('failed', 'stream error');
        $('#tool-run').disabled = false;
        await finishWithDiff();
      };
    } catch (e) {
      setStatus('failed', e.message);
      $('#tool-run').disabled = false;
    }
  }

  // ─── State-diff helpers ────────────────────────────────────────────────

  async function captureSnapshots(scopes) {
    const out = {};
    for (const scope of scopes) {
      if (scope === 'dispute') {
        // Snapshot every L2 chain's dispute system.
        out.dispute = {};
        if (state.snapshot && state.snapshot.l2s) {
          for (const chain of Object.keys(state.snapshot.l2s)) {
            try {
              const r = await fetch('/api/dispute/' + encodeURIComponent(chain));
              if (r.ok) out.dispute[chain] = await r.json();
            } catch (e) {}
          }
        }
      }
    }
    return out;
  }

  function renderSnapshotDiff(scopes, before, after) {
    if (!before || !after) return '';
    let html = '';
    for (const scope of scopes) {
      if (scope === 'dispute' && before.dispute && after.dispute) {
        html += renderDisputeDiff(before.dispute, after.dispute);
      }
    }
    return html;
  }

  function renderDisputeDiff(before, after) {
    const chains = new Set([...Object.keys(before), ...Object.keys(after)]);
    let chainBlocks = '';
    let totalChanges = 0;
    for (const chain of chains) {
      const b = before[chain];
      const a = after[chain];
      if (!b || !a) continue;
      const rows = diffDispute(b, a);
      totalChanges += rows.length;
      if (rows.length === 0) continue;
      chainBlocks += `<div class="diff-chain"><div class="diff-chain-name muted">${escapeHTML(chain)}</div>` +
        rows.map(r => diffRowHTML(r)).join('') + '</div>';
    }
    if (totalChanges === 0) {
      return `<div class="state-diff state-diff-empty">
        <div class="diff-head"><span class="diff-pill diff-pill-none">NO STATE CHANGE</span><span class="muted small">Dispute system snapshot is identical before and after this run.</span></div>
      </div>`;
    }
    return `<div class="state-diff">
      <div class="diff-head"><span class="diff-pill diff-pill-changed">${totalChanges} state change${totalChanges === 1 ? '' : 's'}</span><span class="muted small">Dispute system before vs after this run.</span></div>
      ${chainBlocks}
    </div>`;
  }

  function diffDispute(b, a) {
    const out = [];
    if (b.respected_game_type !== a.respected_game_type) {
      out.push({
        key: 'AnchorStateRegistry.respectedGameType',
        before: `${b.respected_game_type} (${b.respected_game_type_name || '?'})`,
        after: `${a.respected_game_type} (${a.respected_game_type_name || '?'})`,
        kind: 'consensus',
      });
    }
    // Per-game-type impl + bond
    const types = new Map();
    (b.implementations || []).forEach(i => types.set(i.game_type, { name: i.name, before: i }));
    (a.implementations || []).forEach(i => {
      const e = types.get(i.game_type) || { name: i.name };
      e.after = i;
      types.set(i.game_type, e);
    });
    for (const [t, { name, before: bi, after: ai }] of types) {
      if (!bi || !ai) continue;
      if ((bi.impl || '') !== (ai.impl || '')) {
        out.push({
          key: `factory.gameImpls(${t} ${name})`,
          before: shortAddrOrEmpty(bi.impl),
          after: shortAddrOrEmpty(ai.impl),
          kind: ai.registered && !bi.registered ? 'add' : !ai.registered && bi.registered ? 'remove' : 'change',
        });
      }
      if ((bi.init_bond_wei || '0') !== (ai.init_bond_wei || '0')) {
        out.push({
          key: `factory.initBonds(${t} ${name})`,
          before: bi.init_bond_eth + ' ETH',
          after: ai.init_bond_eth + ' ETH',
          kind: 'change',
        });
      }
    }
    if ((b.game_count || 0) !== (a.game_count || 0)) {
      out.push({
        key: 'factory.gameCount',
        before: String(b.game_count || 0),
        after: String(a.game_count || 0),
        kind: 'change',
      });
    }
    return out;
  }

  function shortAddrOrEmpty(a) {
    if (!a || a === '0x0000000000000000000000000000000000000000') return '∅';
    return a;
  }

  function diffRowHTML(r) {
    const kindLabel = {
      'add': 'NEW',
      'remove': 'CLEARED',
      'change': 'CHANGED',
      'consensus': 'CONSENSUS',
    }[r.kind] || 'CHANGED';
    return `<div class="diff-row diff-row-${r.kind}">
      <span class="diff-kind">${kindLabel}</span>
      <span class="diff-key">${escapeHTML(r.key)}</span>
      <span class="diff-values">
        <span class="diff-before"><code>${escapeHTML(r.before)}</code></span>
        <span class="diff-arrow">→</span>
        <span class="diff-after"><code>${escapeHTML(r.after)}</code></span>
      </span>
    </div>`;
  }

  function setStatus(cls, label) {
    const s = $('#tool-status');
    if (!s) return;
    s.className = 'tool-status ' + cls;
    s.querySelector('.label').textContent = label;
  }

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Consensus
  // ────────────────────────────────────────────────────────────────────────

  route('/consensus', async (view) => {
    setCrumbs(['Consensus']);
    view.innerHTML = `
      <div class="page-head"><h1>L2 consensus / dispute system</h1></div>
      <p class="page-sub">How each L2 reaches L1 finality right now: the active dispute game, its timing parameters, and live state of in-progress games. Tools page handles swaps + active-type flips.</p>
      <div id="consensus-content"><div class="empty"><span class="spinner"></span> loading…</div></div>`;
    await renderConsensus();
    // Refetch from server every 15s; tick countdowns client-side every 1s.
    const refetch = setInterval(() => { if (currentPath() !== '/consensus') return clearInterval(refetch); renderConsensus(); }, 15000);
    const tick = setInterval(() => { if (currentPath() !== '/consensus') return clearInterval(tick); tickConsensusCountdowns(); }, 1000);
  });

  async function renderConsensus() {
    const container = $('#consensus-content');
    if (!container) return;
    if (!state.snapshot || !state.snapshot.l2s) {
      container.innerHTML = '<div class="empty"><span class="spinner"></span> waiting for chain state…</div>';
      return;
    }
    const names = Object.keys(state.snapshot.l2s);
    if (names.length === 0) { container.innerHTML = '<div class="empty">No L2 chains.</div>'; return; }
    let html = '';
    for (const name of names) {
      try {
        window._consensusChain = name; // used by per-game action buttons
        const r = await fetch('/api/dispute/' + encodeURIComponent(name));
        if (!r.ok) { html += `<div class="card"><h2>${escapeHTML(name)}</h2><div class="empty">Failed to load: ${r.status}</div></div>`; continue; }
        html += renderConsensusChain(name, await r.json());
      } catch (e) {
        html += `<div class="card"><h2>${escapeHTML(name)}</h2><div class="empty">${escapeHTML(e.message)}</div></div>`;
      }
    }
    container.innerHTML = html;
  }

  function renderConsensusChain(name, snap) {
    const respected = (snap.implementations || []).find(i => i.is_respected) || {};
    const others = (snap.implementations || []).filter(i => i.registered && !i.is_respected);
    const unregistered = (snap.implementations || []).filter(i => !i.registered);

    const respHtml = `
      <div class="consensus-respected">
        <div class="consensus-respected-head">
          <span class="consensus-pill">ACTIVE GAME TYPE ${snap.respected_game_type}</span>
          <span class="consensus-name">${escapeHTML(snap.respected_game_type_name || 'unknown')}</span>
          <span class="consensus-family">${escapeHTML(respected.family || '')}</span>
        </div>
        <div class="consensus-respected-body">
          <div><span class="muted">impl</span> <code>${respected.impl || '—'}</code></div>
          <div><span class="muted">init bond</span> <code>${escapeHTML(respected.init_bond_eth || '0')} ETH</code></div>
        </div>
        <ul class="consensus-explainer">${(snap.explainer || []).map(s => '<li>' + escapeHTML(s) + '</li>').join('')}</ul>
      </div>`;

    const timingHtml = renderActiveTiming(respected);

    const liveHtml = renderLiveGames(snap.recent_games || [], respected);

    const addrsRows = [
      ['DisputeGameFactory', snap.dispute_game_factory, snap.factory_version || ''],
      ['AnchorStateRegistry', snap.anchor_state_registry, ''],
      ['OptimismPortal', snap.optimism_portal, ''],
      ['SystemConfig', snap.system_config, ''],
      ['Factory owner', snap.factory_owner, '(can call setImplementation)'],
    ];
    const addrsHtml = '<table class="kv">' + addrsRows.map(r =>
      `<tr><td>${escapeHTML(r[0])}</td><td><code>${r[1] || '—'}</code> <span class="dim small">${escapeHTML(r[2])}</span></td></tr>`).join('') + '</table>';

    const othersHtml = others.length === 0
      ? '<div class="empty">No other game types registered.</div>'
      : '<table class="consensus-table"><thead><tr><th>Type</th><th>Name</th><th>Family</th><th>Impl</th><th>Bond</th><th>Challenge clock</th></tr></thead><tbody>' +
        others.map(i => `<tr>
          <td>${i.game_type}</td>
          <td>${escapeHTML(i.name)}</td>
          <td class="muted small">${escapeHTML(i.family)}</td>
          <td><code>${shortAddr(i.impl)}</code></td>
          <td>${escapeHTML(i.init_bond_eth)} ETH</td>
          <td class="muted small">${escapeHTML(timingShort(i))}</td>
        </tr>`).join('') + '</tbody></table>';

    const unregHtml = `<details class="collapsible"><summary>${unregistered.length} unregistered game types (potential upgrade targets)</summary>
      <table class="consensus-table"><thead><tr><th>Type</th><th>Name</th><th>Family</th><th class="desc">Description</th></tr></thead><tbody>` +
      unregistered.map(i => `<tr>
        <td>${i.game_type}</td>
        <td>${escapeHTML(i.name)}</td>
        <td class="muted small">${escapeHTML(i.family)}</td>
        <td class="desc">${escapeHTML(i.description)}</td>
      </tr>`).join('') + '</tbody></table></details>';

    return `
      <div class="card">
        <h2>${escapeHTML(name)} <small class="muted">${snap.game_count || 0} games created</small></h2>
        ${respHtml}
        ${timingHtml}
        ${liveHtml}
        <h3>L1 contracts</h3>${addrsHtml}
        <h3>Other registered game types</h3>${othersHtml}
        ${unregHtml}
      </div>`;
  }

  // ─── Live game state + countdowns ──────────────────────────────────────

  function fmtSeconds(s) {
    if (s == null) return '—';
    if (s < 0) s = 0;
    if (s < 60) return s + 's';
    const m = Math.floor(s / 60);
    const r = s % 60;
    if (m < 60) return m + 'm ' + r + 's';
    const h = Math.floor(m / 60);
    const mm = m % 60;
    if (h < 24) return h + 'h ' + mm + 'm ' + r + 's';
    const d = Math.floor(h / 24);
    const hh = h % 24;
    return d + 'd ' + hh + 'h ' + mm + 'm';
  }

  function timingShort(impl) {
    const parts = [];
    if (impl.max_clock_duration_seconds) parts.push('max clock ' + fmtSeconds(impl.max_clock_duration_seconds));
    if (impl.max_challenge_duration_seconds) parts.push('challenge ' + fmtSeconds(impl.max_challenge_duration_seconds));
    if (impl.max_prove_duration_seconds) parts.push('prove ' + fmtSeconds(impl.max_prove_duration_seconds));
    return parts.join(' · ');
  }

  function renderActiveTiming(impl) {
    if (!impl || !impl.registered) return '';
    const rows = [];
    if (impl.max_clock_duration_seconds) {
      rows.push(['Max clock duration', fmtSeconds(impl.max_clock_duration_seconds), 'Total clock budget for either side. Mainnet defaults to 3.5 days.']);
    }
    if (impl.clock_extension_seconds) {
      rows.push(['Clock extension', fmtSeconds(impl.clock_extension_seconds), 'Bonus time given to the responder when a clock would otherwise expire close to a depth change.']);
    }
    if (impl.split_depth) {
      rows.push(['Split depth', String(impl.split_depth), 'Bisection depth at which the trace switches from outputs to MIPS instructions.']);
    }
    if (impl.max_depth) {
      rows.push(['Max depth', String(impl.max_depth), 'Maximum bisection depth — leaf level for instruction-level dispute.']);
    }
    if (impl.max_challenge_duration_seconds) {
      rows.push(['Max challenge duration', fmtSeconds(impl.max_challenge_duration_seconds), 'Window during which a ZK proposal can be challenged.']);
    }
    if (impl.max_prove_duration_seconds) {
      rows.push(['Max prove duration', fmtSeconds(impl.max_prove_duration_seconds), 'Window during which the prover can submit a ZK proof after a challenge.']);
    }
    if (rows.length === 0) return '';
    return `<h3>Active game type — timing</h3>
      <table class="kv">${rows.map(r => `<tr><td>${escapeHTML(r[0])}</td><td><code>${escapeHTML(r[1])}</code> <span class="dim small">${escapeHTML(r[2])}</span></td></tr>`).join('')}</table>`;
  }

  function renderLiveGames(games, respected) {
    if (games.length === 0) {
      return '<h3>Live games</h3><div class="empty">No games created yet.</div>';
    }
    return '<h3>Live games <small class="muted">most recent first</small></h3>' +
      renderProposerCadence(games) +
      '<div class="game-list">' + games.map(g => renderGameCard(g, respected)).join('') + '</div>';
  }

  function renderProposerCadence(games) {
    if (!games || games.length === 0) return '';
    const now = Math.floor(Date.now() / 1000);
    const sorted = games.slice().sort((a, b) => b.created_at - a.created_at);
    const lastAgo = now - sorted[0].created_at;
    let intervalLine = '';
    if (sorted.length >= 2) {
      const intervals = [];
      for (let i = 0; i < sorted.length - 1; i++) {
        intervals.push(sorted[i].created_at - sorted[i + 1].created_at);
      }
      const mean = Math.floor(intervals.reduce((a, b) => a + b, 0) / intervals.length);
      const min = Math.min(...intervals);
      const max = Math.max(...intervals);
      intervalLine = `
        <span><span class="cadence-label">mean interval</span><span class="cadence-value">${escapeHTML(fmtSeconds(mean))}</span></span>
        <span><span class="cadence-label">range</span><span class="cadence-value">${escapeHTML(fmtSeconds(min))} – ${escapeHTML(fmtSeconds(max))}</span></span>`;
    }
    return `<div class="cadence-chip">
      <span><span class="cadence-label">last game</span><span class="cadence-value">${escapeHTML(fmtSeconds(lastAgo))} ago</span></span>
      ${intervalLine}
      <span><span class="cadence-label">tracked</span><span class="cadence-value">${games.length}</span></span>
    </div>`;
  }

  function renderGameCard(g, respected) {
    const isInProgress = g.status === 0;
    const isRespectedType = respected && respected.game_type === g.game_type;
    const statusClass = g.status === 0 ? 'status-running' : g.status === 2 ? 'status-defender' : 'status-challenger';
    const statusLabel = g.status_name || 'IN_PROGRESS';

    const created = `<span class="muted">created</span> ${escapeHTML(fmtTimeAgo(g.created_at))}`;

    let countdown = '';
    if (isInProgress && g.deadline_timestamp) {
      countdown = `<div class="game-countdown" data-deadline="${g.deadline_timestamp}" data-created="${g.created_at}" data-max="${g.max_clock_duration_seconds || 0}">
        <div class="game-countdown-bar"><div class="game-countdown-fill"></div></div>
        <div class="game-countdown-text">
          <span class="game-countdown-remaining">computing…</span>
          <span class="muted small game-countdown-total">/ ${escapeHTML(fmtSeconds(g.max_clock_duration_seconds))}</span>
        </div>
      </div>`;
    }

    const lifecycle = renderGameLifecycle(g);
    const actions = isInProgress
      ? `<div class="game-actions">
          <button class="btn primary game-resolve-btn" data-chain="${escapeHTML(window._consensusChain || 'L2')}" data-addr="${escapeHTML(g.proxy)}" title="Advance L1 time past the deadline, then call resolveClaim() and resolve()">⏩ Resolve now</button>
          <span class="game-resolve-status muted small"></span>
        </div>`
      : '';

    return `<div class="game-card ${statusClass} ${isRespectedType ? '' : 'game-unrespected'}">
      <div class="game-head">
        <span class="game-idx">#${g.index}</span>
        <span class="game-type-name">${escapeHTML(g.game_type_name)}</span>
        <span class="pill game-status">${escapeHTML(statusLabel)}</span>
        ${!isRespectedType ? '<span class="muted small">non-active type</span>' : ''}
      </div>
      <div class="game-meta">
        ${created}
        ${g.l2_sequence_number ? '· <span class="muted">L2 #' + g.l2_sequence_number + '</span>' : ''}
        · <a href="#/explorer/L1/address/${escapeHTML(g.proxy)}"><code>${shortAddr(g.proxy)}</code></a>
      </div>
      ${countdown}
      ${lifecycle}
      ${actions}
    </div>`;
  }

  async function resolveGame(chain, addr, btn) {
    const card = btn.closest('.game-card');
    const status = card.querySelector('.game-resolve-status');
    btn.disabled = true;
    status.innerHTML = '<span class="spinner"></span> advancing time…';
    try {
      const r = await fetch('/api/dispute/' + encodeURIComponent(chain) + '/games/' + encodeURIComponent(addr) + '/resolve', { method: 'POST' });
      const body = await r.json();
      if (!r.ok) {
        const detail = body && body.note ? body.note : ('HTTP ' + r.status);
        status.innerHTML = '<span style="color:var(--red)">failed:</span> ' + escapeHTML(detail);
        btn.disabled = false;
        return;
      }
      const advanced = body.advanced_seconds ? ' (advanced ' + fmtSeconds(body.advanced_seconds) + ')' : '';
      const txLinks = [];
      if (body.resolve_claim_tx) txLinks.push(`<a href="#/explorer/L1/tx/${body.resolve_claim_tx}"><code>resolveClaim</code></a>`);
      if (body.resolve_tx) txLinks.push(`<a href="#/explorer/L1/tx/${body.resolve_tx}"><code>resolve</code></a>`);
      status.innerHTML = `<span style="color:var(--green)">${escapeHTML(body.post_status_name || 'resolved')}</span>${advanced} · ` + txLinks.join(' · ');
      // Force a server refetch so the lifecycle + status flip immediately.
      await renderConsensus();
    } catch (e) {
      status.innerHTML = '<span style="color:var(--red)">failed:</span> ' + escapeHTML(e.message);
      btn.disabled = false;
    }
  }

  // Delegated click handler for the consensus content area.
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('.game-resolve-btn');
    if (!btn) return;
    e.preventDefault();
    resolveGame(btn.getAttribute('data-chain'), btn.getAttribute('data-addr'), btn);
  });

  // ─── Lifecycle visualization ────────────────────────────────────────────

  // Stage definitions per game-type family. Each stage has a label and a
  // short tooltip describing what happens. The compute function returns the
  // current stage index (0-based) given a game.
  const LIFECYCLE_FAULT_PROOF = {
    stages: [
      { label: 'Created', tooltip: 'Game proxy deployed via factory.create(). Proposer posts the root claim and the init bond.' },
      { label: 'Challenge clock', tooltip: 'Anyone (or the whitelisted challenger, for permissioned variants) can challenge or counter the root claim. Each move bisects deeper into the trace, eating clock time.' },
      { label: 'Resolvable', tooltip: 'Both sides ran out of clock or the bisection finished. The game is ready for anyone to call resolveClaim() then resolve().' },
      { label: 'Resolved', tooltip: 'status flipped to DEFENDER_WINS or CHALLENGER_WINS. Bonds get distributed; the anchor state can advance.' },
    ],
    compute: (g) => {
      if (g.status !== 0) return 3;
      const now = Math.floor(Date.now() / 1000);
      if (g.deadline_timestamp && now < g.deadline_timestamp) return 1;
      return 2;
    },
  };

  const LIFECYCLE_ZK = {
    stages: [
      { label: 'Created', tooltip: 'Proposer posts a root claim and init bond.' },
      { label: 'Challenge window', tooltip: 'Anyone can challenge by posting a counter-bond. If nobody challenges before the window closes, the proposer wins.' },
      { label: 'Prove window', tooltip: 'Once challenged, the prover must submit a valid ZK proof of the claim before this window closes.' },
      { label: 'Resolved', tooltip: 'Defender wins if a valid proof was submitted, challenger wins otherwise.' },
    ],
    compute: (g) => {
      if (g.status !== 0) return 3;
      // Without per-claim state we can't tell challenged vs unchallenged; show
      // window 1 by default.
      const now = Math.floor(Date.now() / 1000);
      if (g.deadline_timestamp && now < g.deadline_timestamp) return 1;
      return 2;
    },
  };

  function lifecycleForGameType(name) {
    if (name === 'ZK_DISPUTE_GAME') return LIFECYCLE_ZK;
    if (name === 'OP_SUCCINCT') return LIFECYCLE_ZK;
    // CANNON, PERMISSIONED_CANNON, ASTERISC, *_KONA, SUPER_*_CANNON: fault-proof flow.
    return LIFECYCLE_FAULT_PROOF;
  }

  function renderGameLifecycle(g) {
    const lc = lifecycleForGameType(g.game_type_name);
    const current = lc.compute(g);
    const cells = lc.stages.map((s, i) => {
      let cls = '';
      if (i < current) cls = 'past';
      else if (i === current) cls = 'current';
      else cls = 'future';
      return `<div class="lc-stage ${cls}" title="${escapeHTML(s.tooltip)}">
        <div class="lc-dot"></div>
        <div class="lc-label">${escapeHTML(s.label)}</div>
      </div>`;
    });
    const conns = lc.stages.slice(0, -1).map((_, i) =>
      `<div class="lc-conn ${i < current ? 'active' : ''}"></div>`
    );
    // Interleave cells and connectors.
    let html = '';
    for (let i = 0; i < cells.length; i++) {
      html += cells[i];
      if (conns[i]) html += conns[i];
    }
    return `<div class="game-lifecycle">${html}</div>`;
  }

  function tickConsensusCountdowns() {
    const now = Math.floor(Date.now() / 1000);
    for (const el of document.querySelectorAll('.game-countdown')) {
      const deadline = parseInt(el.getAttribute('data-deadline') || '0', 10);
      const created = parseInt(el.getAttribute('data-created') || '0', 10);
      const max = parseInt(el.getAttribute('data-max') || '0', 10);
      if (!deadline || !created || !max) continue;
      const remaining = deadline - now;
      const elapsed = Math.max(0, Math.min(max, now - created));
      const pct = Math.min(100, Math.max(0, (elapsed / max) * 100));
      const fill = el.querySelector('.game-countdown-fill');
      if (fill) {
        fill.style.width = pct.toFixed(1) + '%';
        if (remaining <= 0) {
          fill.classList.add('expired');
        } else if (remaining < max * 0.1) {
          fill.classList.add('warning');
        }
      }
      const txt = el.querySelector('.game-countdown-remaining');
      if (txt) {
        if (remaining <= 0) {
          txt.textContent = 'expired (window closed)';
          txt.classList.add('expired');
        } else {
          txt.textContent = fmtSeconds(remaining) + ' remaining';
        }
      }

      // Drive the lifecycle viz alongside the countdown — if the deadline has
      // crossed, advance the current stage from "Challenge clock" to "Resolvable"
      // without waiting for the next server refetch.
      const card = el.closest('.game-card');
      if (card && remaining <= 0) {
        const stages = card.querySelectorAll('.lc-stage');
        const conns = card.querySelectorAll('.lc-conn');
        // For fault-proof flow: advance stage 1 → past, stage 2 → current.
        if (stages.length === 4 && stages[1].classList.contains('current')) {
          stages[1].classList.remove('current');
          stages[1].classList.add('past');
          if (conns[1]) conns[1].classList.add('active');
          stages[2].classList.remove('future');
          stages[2].classList.add('current');
        }
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Activity (live event log)
  // ────────────────────────────────────────────────────────────────────────

  route('/activity', (view) => {
    setCrumbs(['Activity']);
    view.innerHTML = `
      <div class="page-head"><h1>Activity <small>L1/L2 blocks, control actions, script runs</small></h1></div>
      <p class="page-sub">Live stream of every event the playground emits. Useful when debugging "what happened just now?"</p>
      <div class="card"><div id="events-log" class="events-log"></div></div>`;
    const log = $('#events-log');
    function append(evt, prepend) {
      const div = document.createElement('div');
      div.className = 'evt' + (prepend ? ' highlight' : '');
      const t = new Date(evt.time).toLocaleTimeString();
      let detail = '';
      try { const d = JSON.parse(evt.data); detail = JSON.stringify(d.data || d); } catch (e) { detail = evt.data || ''; }
      div.innerHTML = `<span class="evt-time">${escapeHTML(t)}</span><span class="evt-type">${escapeHTML(evt.type)}</span><span class="evt-data">${escapeHTML(detail)}</span>`;
      if (prepend) log.prepend(div);
      else log.append(div);
      while (log.children.length > 500) log.lastChild.remove();
    }
    // Replay buffered events oldest→newest, then live-append new ones.
    state.eventLog.slice().reverse().forEach(e => append(e, false));
    const listener = e => append(e, true);
    state.eventListeners.push(listener);
    // Cleanup on route change.
    const cleanup = () => {
      state.eventListeners = state.eventListeners.filter(l => l !== listener);
      window.removeEventListener('hashchange', cleanup);
    };
    window.addEventListener('hashchange', cleanup);
  });

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Network (RPCs, account, contracts)
  // ────────────────────────────────────────────────────────────────────────

  route('/network', async (view) => {
    setCrumbs(['Network']);
    if (!state.chains.length) await loadChains();
    const s = state.snapshot;
    let html = `
      <div class="page-head"><h1>Network</h1></div>
      <p class="page-sub">Endpoints, accounts, and contracts you'll need to point your tooling at the playground.</p>`;

    if (s && s.account) {
      html += `
        <div class="card">
          <h2>Test account</h2>
          ${addrRow('Address', s.account.address)}
          ${addrRow('Private key', s.account.private_key, true)}
          <div class="dim small" style="margin-top:8px">Pre-funded on L1 and L2. The playground also derives the L1ProxyAdminOwner and SuperchainConfigGuardian devkeys (visible to the bundled tools as <code>OP_PG_OWNER_PRIVKEY</code> and <code>OP_PG_GUARDIAN_PRIVKEY</code>).</div>
        </div>`;
    }

    html += `<div class="card"><h2>RPC endpoints</h2>` +
      state.chains.map(c => addrRow(c.name + ' RPC', c.rpc) + addrRow(c.name + ' WS', c.ws)).join('') +
      `</div>`;

    // Pull L1 contract addresses from each L2's dispute snapshot.
    if (s && s.l2s) {
      for (const name of Object.keys(s.l2s)) {
        try {
          const r = await fetch('/api/dispute/' + encodeURIComponent(name));
          if (!r.ok) continue;
          const d = await r.json();
          html += `<div class="card"><h2>L1 contracts for ${escapeHTML(name)}</h2>
            ${addrRow('SystemConfig', d.system_config)}
            ${addrRow('OptimismPortal', d.optimism_portal)}
            ${addrRow('DisputeGameFactory', d.dispute_game_factory)}
            ${addrRow('AnchorStateRegistry', d.anchor_state_registry)}
            ${addrRow('Factory owner', d.factory_owner)}
          </div>`;
        } catch (e) {}
      }
    }

    view.innerHTML = html;
    view.querySelectorAll('.copy-btn').forEach(btn => {
      btn.addEventListener('click', () => copyText(btn.getAttribute('data-text')));
    });
  });

  function addrRow(label, value, secret) {
    if (!value) return '';
    const display = secret ? value.slice(0, 10) + '…' + value.slice(-8) : value;
    return `<div class="addr-row">
      <span class="label">${escapeHTML(label)}</span>
      <code>${escapeHTML(display)}</code>
      <button class="copy-btn" data-text="${escapeHTML(value)}" title="Copy">⧉</button>
    </div>`;
  }

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Explorer (placeholder)
  // ────────────────────────────────────────────────────────────────────────

  // ────────────────────────────────────────────────────────────────────────
  // VIEW: Explorer (block list, block detail, tx detail)
  // ────────────────────────────────────────────────────────────────────────

  route('/explorer', async (view) => {
    setCrumbs(['Explorer']);
    view.innerHTML = `
      <div class="page-head"><h1>Explorer</h1></div>
      <div id="explorer-tabs"></div>
      <div id="explorer-body"></div>`;
    await renderExplorer(null);
  });

  route('/explorer/:chain', async (view, params) => {
    setCrumbs([{ label: 'Explorer', href: '/explorer' }, params.chain]);
    view.innerHTML = `
      <div class="page-head"><h1>Explorer <small>${escapeHTML(params.chain)}</small></h1></div>
      <div id="explorer-tabs"></div>
      <div id="explorer-body"></div>`;
    await renderExplorer(params.chain);
  });

  route('/explorer/:chain/block/:ref', async (view, params) => {
    setCrumbs([
      { label: 'Explorer', href: '/explorer' },
      { label: params.chain, href: '/explorer/' + params.chain },
      'Block ' + params.ref,
    ]);
    view.innerHTML = `<div class="page-head"><h1>Block ${escapeHTML(params.ref)} <small>${escapeHTML(params.chain)}</small></h1></div>
      <div id="block-body"><div class="empty"><span class="spinner"></span> loading…</div></div>`;
    try {
      const r = await fetch('/api/explorer/' + encodeURIComponent(params.chain) + '/block/' + encodeURIComponent(params.ref));
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const b = await r.json();
      $('#block-body').innerHTML = renderBlockDetail(params.chain, b);
    } catch (e) {
      $('#block-body').innerHTML = '<div class="empty">Failed: ' + escapeHTML(e.message) + '</div>';
    }
  });

  route('/explorer/:chain/address/:addr', async (view, params) => {
    setCrumbs([
      { label: 'Explorer', href: '/explorer' },
      { label: params.chain, href: '/explorer/' + params.chain },
      'Address ' + params.addr.slice(0, 10) + '…',
    ]);
    view.innerHTML = `<div class="page-head"><h1>Address <small>${escapeHTML(params.chain)}</small></h1></div>
      <div id="addr-body"><div class="empty"><span class="spinner"></span> loading…</div></div>`;
    try {
      const r = await fetch('/api/explorer/' + encodeURIComponent(params.chain) + '/address/' + encodeURIComponent(params.addr));
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const d = await r.json();
      $('#addr-body').innerHTML = renderAddressDetail(params.chain, d);
    } catch (e) {
      $('#addr-body').innerHTML = '<div class="empty">Failed: ' + escapeHTML(e.message) + '</div>';
    }
  });

  function renderAddressDetail(chain, d) {
    const kind = d.is_contract ? 'Contract' : 'EOA';
    const head = `<table class="kv">
      <tr><td>Address</td><td><code>${escapeHTML(d.address)}</code> ${d.name ? '<span class="pill" style="background:var(--accent);color:white">' + escapeHTML(d.name) + '</span>' : ''}</td></tr>
      <tr><td>Type</td><td>${kind} ${d.is_contract ? '· code size <span class="muted">' + d.code_size.toLocaleString() + ' bytes</span>' : ''}</td></tr>
      <tr><td>Balance</td><td><code>${escapeHTML(d.balance_eth || '0')} ETH</code> <span class="muted small">${escapeHTML(d.balance_wei || '0')} wei</span></td></tr>
      <tr><td>Nonce</td><td>${d.nonce}</td></tr>
    </table>`;

    const abiBlock = (d.abi_functions && d.abi_functions.length)
      ? `<div class="card"><h2>Known interface <small class="muted">${d.name}</small></h2>
          <h3>Functions</h3>
          <ul class="abi-list">${d.abi_functions.map(f => '<li><code>' + escapeHTML(f) + '</code></li>').join('')}</ul>
          ${(d.abi_events && d.abi_events.length) ? '<h3>Events</h3><ul class="abi-list">' + d.abi_events.map(e => '<li><code>' + escapeHTML(e) + '</code></li>').join('') + '</ul>' : ''}
        </div>`
      : '';

    const txsBlock = (d.recent_txs && d.recent_txs.length)
      ? `<div class="card"><h2>Recent transactions <small class="muted">scanned blocks ${d.scanned_from_block}–${d.scanned_to_block}, ${d.recent_txs.length} hits</small></h2>
          <table class="table"><thead><tr><th>Hash</th><th>Block</th><th>Dir</th><th>From</th><th>To</th><th>Value (wei)</th></tr></thead><tbody>` +
          d.recent_txs.map(tx => `<tr>
            <td><a href="#/explorer/${encodeURIComponent(chain)}/tx/${tx.hash}"><code>${shortHash(tx.hash)}</code></a></td>
            <td><a href="#/explorer/${encodeURIComponent(chain)}/block/${tx.block_number}">${tx.block_number.toLocaleString()}</a></td>
            <td><span class="dir-${tx.direction}">${tx.direction.toUpperCase()}</span></td>
            <td><a href="#/explorer/${encodeURIComponent(chain)}/address/${tx.from}"><code>${shortAddr(tx.from)}</code></a></td>
            <td>${tx.to ? '<a href="#/explorer/' + encodeURIComponent(chain) + '/address/' + tx.to + '"><code>' + shortAddr(tx.to) + '</code></a>' : '<span class="muted">—</span>'}</td>
            <td>${escapeHTML(tx.value_wei)}</td>
          </tr>`).join('') + '</tbody></table></div>'
      : `<div class="card"><h2>Recent transactions</h2><div class="empty">No transactions found in the last ${d.scanned_to_block - d.scanned_from_block} blocks (scanned ${d.scanned_from_block}–${d.scanned_to_block}).</div></div>`;

    return `<div class="card"><h2>Account</h2>${head}</div>${abiBlock}${txsBlock}`;
  }

  route('/explorer/:chain/tx/:hash', async (view, params) => {
    setCrumbs([
      { label: 'Explorer', href: '/explorer' },
      { label: params.chain, href: '/explorer/' + params.chain },
      'Tx ' + params.hash.slice(0, 10) + '…',
    ]);
    view.innerHTML = `<div class="page-head"><h1>Transaction <small>${escapeHTML(params.chain)}</small></h1></div>
      <div id="tx-body"><div class="empty"><span class="spinner"></span> loading…</div></div>`;
    try {
      const r = await fetch('/api/explorer/' + encodeURIComponent(params.chain) + '/tx/' + encodeURIComponent(params.hash));
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const tx = await r.json();
      $('#tx-body').innerHTML = renderTxDetail(params.chain, tx);

      // Lazy-load the call trace if the user expands it.
      const traceHost = $('#tx-trace-host');
      if (traceHost) {
        const summary = traceHost.querySelector('summary');
        let loaded = false;
        traceHost.addEventListener('toggle', async () => {
          if (loaded || !traceHost.open) return;
          loaded = true;
          const target = $('#tx-trace');
          target.innerHTML = '<div class="empty"><span class="spinner"></span> tracing…</div>';
          try {
            const tr = await fetch('/api/explorer/' + encodeURIComponent(params.chain) + '/tx/' + encodeURIComponent(params.hash) + '/trace');
            if (!tr.ok) throw new Error('HTTP ' + tr.status + ' — debug_traceTransaction may be disabled on this RPC');
            const root = await tr.json();
            target.innerHTML = renderCallTree(root, 0);
          } catch (e) {
            target.innerHTML = '<div class="empty">Failed: ' + escapeHTML(e.message) + '</div>';
          }
        });
      }
    } catch (e) {
      $('#tx-body').innerHTML = '<div class="empty">Failed: ' + escapeHTML(e.message) + '</div>';
    }
  });

  let explorerChains = null;
  async function loadExplorerChains() {
    if (explorerChains) return explorerChains;
    try {
      const r = await fetch('/api/explorer/chains');
      explorerChains = r.ok ? await r.json() : [];
    } catch (e) { explorerChains = []; }
    return explorerChains;
  }

  async function renderExplorer(activeChain) {
    const chains = await loadExplorerChains();
    if (chains.length === 0) {
      $('#explorer-body').innerHTML = '<div class="empty">No chains exposed.</div>';
      return;
    }
    if (!activeChain) activeChain = chains[0];
    $('#explorer-tabs').innerHTML = '<div class="tabs">' + chains.map(c =>
      `<a class="tab ${c === activeChain ? 'active' : ''}" href="#/explorer/${encodeURIComponent(c)}">${escapeHTML(c)}</a>`
    ).join('') + '</div>';
    $('#explorer-body').innerHTML = '<div class="empty"><span class="spinner"></span> loading blocks…</div>';
    try {
      const r = await fetch('/api/explorer/' + encodeURIComponent(activeChain) + '/blocks');
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const blocks = await r.json();
      $('#explorer-body').innerHTML = renderBlocksList(activeChain, blocks);
    } catch (e) {
      $('#explorer-body').innerHTML = '<div class="empty">Failed: ' + escapeHTML(e.message) + '</div>';
    }
  }

  function renderBlocksList(chain, blocks) {
    if (!blocks || blocks.length === 0) return '<div class="empty">No blocks yet.</div>';
    const rows = blocks.map(b => `
      <tr>
        <td><a href="#/explorer/${encodeURIComponent(chain)}/block/${b.number}">${b.number.toLocaleString()}</a></td>
        <td><code>${shortHash(b.hash)}</code></td>
        <td class="muted">${escapeHTML(fmtTimeAgo(b.timestamp))}</td>
        <td>${b.tx_count}</td>
        <td class="muted small">${b.gas_used.toLocaleString()} / ${b.gas_limit.toLocaleString()}</td>
      </tr>`).join('');
    return `<div class="card">
      <table class="table">
        <thead><tr><th>Block</th><th>Hash</th><th>Time</th><th>Txs</th><th class="muted small">Gas used / limit</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
  }

  function renderBlockDetail(chain, b) {
    const meta = `<table class="kv">
      <tr><td>Number</td><td>${b.number.toLocaleString()}</td></tr>
      <tr><td>Hash</td><td><code>${escapeHTML(b.hash)}</code></td></tr>
      <tr><td>Parent</td><td><a href="#/explorer/${encodeURIComponent(chain)}/block/${b.parent_hash}"><code>${shortHash(b.parent_hash)}</code></a></td></tr>
      <tr><td>State root</td><td><code>${shortHash(b.state_root, 18)}</code></td></tr>
      <tr><td>Timestamp</td><td>${escapeHTML(new Date(b.timestamp * 1000).toISOString())} <span class="muted small">(${escapeHTML(fmtTimeAgo(b.timestamp))})</span></td></tr>
      <tr><td>Miner</td><td><code>${escapeHTML(b.miner)}</code></td></tr>
      <tr><td>Gas used / limit</td><td>${b.gas_used.toLocaleString()} / ${b.gas_limit.toLocaleString()}</td></tr>
      ${b.base_fee_wei ? `<tr><td>Base fee (wei)</td><td>${escapeHTML(b.base_fee_wei)}</td></tr>` : ''}
    </table>`;

    const txs = (b.transactions || []).length === 0
      ? '<div class="empty">No transactions in this block.</div>'
      : '<table class="table"><thead><tr><th>Hash</th></tr></thead><tbody>' +
        b.transactions.map(h => `<tr><td><a href="#/explorer/${encodeURIComponent(chain)}/tx/${h}"><code>${escapeHTML(h)}</code></a></td></tr>`).join('') +
        '</tbody></table>';

    return `<div class="card"><h2>Header</h2>${meta}</div>
      <div class="card"><h2>Transactions <small class="muted">${(b.transactions || []).length}</small></h2>${txs}</div>`;
  }

  function renderTxDetail(chain, t) {
    const statusBadge = t.status === 1
      ? '<span class="pill" style="background:var(--green);color:white">SUCCESS</span>'
      : '<span class="pill" style="background:var(--red);color:white">REVERTED</span>';

    const headerRows = `<table class="kv">
      <tr><td>Hash</td><td><code>${escapeHTML(t.hash)}</code></td></tr>
      <tr><td>Status</td><td>${statusBadge}</td></tr>
      <tr><td>Block</td><td><a href="#/explorer/${encodeURIComponent(chain)}/block/${t.block_number}">${t.block_number.toLocaleString()}</a> · index ${t.index}</td></tr>
      <tr><td>From</td><td><code>${escapeHTML(t.from)}</code></td></tr>
      ${t.to ? `<tr><td>To</td><td><code>${escapeHTML(t.to)}</code></td></tr>` : ''}
      ${t.contract_address ? `<tr><td>Contract created</td><td><code>${escapeHTML(t.contract_address)}</code></td></tr>` : ''}
      <tr><td>Value (wei)</td><td>${escapeHTML(t.value_wei)}</td></tr>
      <tr><td>Nonce</td><td>${t.nonce}</td></tr>
      <tr><td>Gas used / limit</td><td>${t.gas_used.toLocaleString()} / ${t.gas_limit.toLocaleString()}</td></tr>
      ${t.gas_price_wei ? `<tr><td>Gas price (wei)</td><td>${escapeHTML(t.gas_price_wei)}</td></tr>` : ''}
      <tr><td>Type</td><td>${t.type}</td></tr>
    </table>`;

    let callBlock = '';
    if (t.decoded_call) {
      callBlock = `<div class="card">
        <h2>Decoded call</h2>
        <div class="decoded-call">
          <div class="decoded-head"><span class="muted">Contract</span> <strong>${escapeHTML(t.decoded_call.contract)}</strong>
            <span class="muted">Method</span> <code>${escapeHTML(t.decoded_call.method)}</code>
            <span class="muted small">selector ${escapeHTML(t.decoded_call.selector)}</span></div>
          ${(t.decoded_call.arguments || []).length === 0 ? '' : '<table class="kv">' +
            t.decoded_call.arguments.map(a =>
              `<tr><td>${escapeHTML(a.name || '')} <span class="dim small">${escapeHTML(a.type)}</span></td><td><code>${escapeHTML(a.value)}</code></td></tr>`
            ).join('') + '</table>'}
        </div>
      </div>`;
    }

    let calldataBlock = `<details class="collapsible" style="margin-top:8px"><summary>Raw input data</summary>
      <pre class="tool-output">${escapeHTML(t.input_hex)}</pre></details>`;

    let logsBlock = '';
    if ((t.logs || []).length > 0) {
      logsBlock = `<div class="card"><h2>Logs <small class="muted">${t.logs.length}</small></h2>` +
        t.logs.map((l, i) => `
          <div class="log-row">
            <div class="log-head">
              <span class="log-idx muted">#${i}</span>
              <code>${escapeHTML(l.address)}</code>
              ${l.contract ? `<span class="pill muted">${escapeHTML(l.contract)}</span>` : ''}
              ${l.event ? `<strong>${escapeHTML(l.event)}</strong>` : `<span class="muted small">topic0 ${escapeHTML(l.topic0 || '')}</span>`}
            </div>
            ${(l.args || []).length === 0 ? '' : '<table class="kv">' +
              l.args.map(a =>
                `<tr><td>${escapeHTML(a.name || '')} <span class="dim small">${escapeHTML(a.type)}</span></td><td><code>${escapeHTML(a.value)}</code></td></tr>`
              ).join('') + '</table>'}
          </div>`).join('') +
        '</div>';
    } else {
      logsBlock = `<div class="card"><h2>Logs</h2><div class="empty">No logs emitted.</div></div>`;
    }

    const traceBlock = `<div class="card">
      <details id="tx-trace-host">
        <summary><h2 style="display:inline">Call trace <small class="muted">click to load</small></h2></summary>
        <div id="tx-trace" style="margin-top:8px"></div>
      </details>
    </div>`;

    return `<div class="card"><h2>Header</h2>${headerRows}</div>
      ${callBlock}
      <div class="card"><h2>Calldata</h2>${calldataBlock}</div>
      ${logsBlock}
      ${traceBlock}`;
  }

  // ─── Call tree renderer ────────────────────────────────────────────────

  function gasFromHex(h) {
    if (!h) return null;
    try { return parseInt(h, 16); } catch (e) { return null; }
  }

  function renderCallTree(node, depth) {
    if (!node) return '<div class="empty">no trace</div>';
    return '<div class="call-tree">' + renderCallFrame(node, depth) + '</div>';
  }

  function renderCallFrame(node, depth) {
    const failed = !!(node.error || node.revert_reason);
    const decoded = node.decoded;
    const gasUsed = gasFromHex(node.gas_used);
    const value = node.value && node.value !== '0x0' ? node.value : null;

    const head = `
      <div class="call-frame ${failed ? 'failed' : ''}" style="padding-left: ${depth * 16}px">
        <div class="call-line">
          <span class="call-type">${escapeHTML(node.type || 'CALL')}</span>
          ${node.contract ? `<span class="pill muted">${escapeHTML(node.contract)}</span>` : ''}
          ${decoded ? `<code class="call-method">${escapeHTML(decoded.method)}</code>` :
            (node.selector ? `<code class="call-selector">${escapeHTML(node.selector)}</code>` : '')}
          ${node.to ? `<span class="muted small">→ <code>${escapeHTML(node.to.slice(0, 6) + '…' + node.to.slice(-4))}</code></span>` : ''}
          ${gasUsed != null ? `<span class="dim small">${gasUsed.toLocaleString()} gas</span>` : ''}
          ${value ? `<span class="dim small">value ${escapeHTML(value)}</span>` : ''}
          ${failed ? `<span class="pill" style="background:var(--red);color:white">REVERT</span>` : ''}
        </div>
        ${decoded && (decoded.arguments || []).length ? renderCallArgs(decoded.arguments, depth) : ''}
        ${node.revert_reason ? `<div class="call-revert" style="margin-left: ${depth * 16 + 22}px"><span class="muted small">reason:</span> <code>${escapeHTML(node.revert_reason)}</code></div>` : ''}
      </div>`;

    const children = (node.children || []).map(c => renderCallFrame(c, depth + 1)).join('');
    return head + children;
  }

  function renderCallArgs(args, depth) {
    return `<div class="call-args" style="margin-left: ${depth * 16 + 22}px">` +
      args.map(a =>
        `<span class="call-arg"><span class="muted">${escapeHTML(a.name || '')}</span> <span class="dim small">${escapeHTML(a.type)}</span> <code>${escapeHTML(a.value)}</code></span>`
      ).join('') + '</div>';
  }

  // ────────────────────────────────────────────────────────────────────────
  // Boot
  // ────────────────────────────────────────────────────────────────────────

  (async function boot() {
    await Promise.all([pollSnapshot(), loadChains()]);
    setupSSE();
    if (!location.hash) location.hash = '#/';
    dispatch();
  })();
})();
