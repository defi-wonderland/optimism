(function() {
  const startTime = Date.now();
  let state = null;

  function $(sel) { return document.querySelector(sel); }
  function fmt(n) { return n != null ? n.toLocaleString() : '-'; }
  function shortHash(h) { return h ? h.slice(0, 10) + '...' : '-'; }
  function uptimeStr() {
    const s = Math.floor((Date.now() - startTime) / 1000);
    const m = Math.floor(s / 60);
    return m > 0 ? m + 'm ' + (s % 60) + 's' : s + 's';
  }

  function renderState(s) {
    state = s;
    $('#mode').textContent = s.mode + ' mode';
    $('#uptime').textContent = uptimeStr();
    $('#acct-addr').textContent = s.account.address;
    $('#acct-key').textContent = s.account.private_key;

    // L1
    $('#l1-head').textContent = fmt(s.l1.head.number) + ' ' + shortHash(s.l1.head.hash);
    $('#l1-finalized').textContent = fmt(s.l1.finalized.number);

    // L2 chains
    const grid = $('#grid');
    for (const [name, l2] of Object.entries(s.l2s)) {
      let card = document.getElementById('card-' + name);
      if (!card) {
        card = document.createElement('section');
        card.className = 'chain-card';
        card.id = 'card-' + name;
        card.innerHTML = `
          <h2>${name} <small style="color:#484f58;font-size:12px">(chain ${l2.chain_id})</small></h2>
          <table>
            <tr><td>Unsafe</td><td class="unsafe">-</td></tr>
            <tr><td>Cross-unsafe</td><td class="cross-unsafe">-</td></tr>
            <tr><td>Local-safe</td><td class="local-safe">-</td></tr>
            <tr><td>Safe</td><td class="safe">-</td></tr>
            <tr><td>Finalized</td><td class="finalized">-</td></tr>
            <tr><td>L1 Origin</td><td class="l1-origin">-</td></tr>
            <tr><td>Sequencer</td><td class="seq-status">-</td></tr>
            <tr><td>Batcher</td><td class="bat-status">-</td></tr>
          </table>
          <div class="controls">
            <button onclick="ctrl('sequencer','${name}','start')">Start Seq</button>
            <button onclick="ctrl('sequencer','${name}','stop')">Stop Seq</button>
            <button onclick="ctrl('sequencer','${name}','step')">Step 1 Block</button>
            <button onclick="ctrl('batcher','${name}','start')">Start Batch</button>
            <button onclick="ctrl('batcher','${name}','stop')">Stop Batch</button>
          </div>`;
        grid.appendChild(card);
      }
      card.querySelector('.unsafe').textContent = fmt(l2.unsafe.number) + ' ' + shortHash(l2.unsafe.hash);
      card.querySelector('.cross-unsafe').textContent = fmt(l2.cross_unsafe.number);
      card.querySelector('.local-safe').textContent = fmt(l2.local_safe.number);
      card.querySelector('.safe').textContent = fmt(l2.safe.number);
      card.querySelector('.finalized').textContent = fmt(l2.finalized.number);
      card.querySelector('.l1-origin').textContent = fmt(l2.current_l1.number);
      const seqEl = card.querySelector('.seq-status');
      seqEl.textContent = l2.sequencer_active ? 'RUNNING' : 'STOPPED';
      seqEl.style.color = l2.sequencer_active ? '#3fb950' : '#f85149';
      const batEl = card.querySelector('.bat-status');
      batEl.textContent = l2.batcher_running ? 'RUNNING' : 'STOPPED';
      batEl.style.color = l2.batcher_running ? '#3fb950' : '#f85149';
    }

    // Supernode
    if (s.supernode) {
      const panel = $('#supernode-panel');
      panel.style.display = '';
      $('#sup-safe-ts').textContent = s.supernode.safe_timestamp;
      $('#sup-local-safe-ts').textContent = s.supernode.local_safe_timestamp;
      let html = '';
      for (const [id, info] of Object.entries(s.supernode.chains || {})) {
        html += `<div>Chain ${id}: cross-unsafe=#${info.cross_unsafe} local-safe=#${info.local_safe} safe=#${info.safe}</div>`;
      }
      $('#sup-chains').innerHTML = html;
    }
  }

  function addEvent(evt) {
    const log = $('#event-log');
    const div = document.createElement('div');
    div.className = 'evt highlight';
    const t = new Date(evt.time).toLocaleTimeString();
    let detail = '';
    try { const d = JSON.parse(evt.data); detail = JSON.stringify(d.data || d); } catch(e) { detail = evt.data; }
    div.innerHTML = `<span class="evt-time">${t}</span><span class="evt-type">${evt.type}</span>${detail}`;
    log.prepend(div);
    while (log.children.length > 200) log.lastChild.remove();
  }

  // Poll state
  async function poll() {
    try {
      const r = await fetch('/api/state');
      if (r.ok) renderState(await r.json());
    } catch(e) {}
  }
  setInterval(poll, 1000);
  poll();

  // SSE events
  const evtSource = new EventSource('/api/events');
  evtSource.onmessage = function(e) {
    try { addEvent(JSON.parse(e.data)); } catch(ex) {}
  };
  ['l1.block','l2.block','control.sequencer.start','control.sequencer.stop','control.batcher.start','control.batcher.stop'].forEach(function(type) {
    evtSource.addEventListener(type, function(e) {
      try { addEvent({ type: type, time: new Date().toISOString(), data: e.data }); } catch(ex) {}
    });
  });

  // Advance time
  window.advanceTime = async function(seconds) {
    try {
      const r = await fetch('/api/control/advance-time?seconds=' + seconds, { method: 'POST' });
      const body = await r.json();
      if (body.error) alert(body.error);
    } catch(e) { alert('Request failed: ' + e.message); }
  };

  // Control API
  window.ctrl = async function(component, chain, action) {
    try {
      const r = await fetch(`/api/control/${component}/${chain}/${action}`, { method: 'POST' });
      const body = await r.json();
      if (body.error) alert(body.error);
    } catch(e) { alert('Request failed: ' + e.message); }
  };

  // Scripts
  async function loadScripts() {
    try {
      const r = await fetch('/api/scripts');
      if (!r.ok) return;
      const scripts = await r.json();
      window._scripts = scripts;
      const container = $('#script-buttons');
      if (!scripts || scripts.length === 0) {
        container.innerHTML = '<span class="muted">No scripts found</span>';
        return;
      }
      scripts.forEach(function(s) {
        const btn = document.createElement('button');
        btn.textContent = s.name;
        btn.title = s.description || s.name;
        btn.onclick = function() { runScript(s.name); };
        container.appendChild(btn);
      });
    } catch(e) {}
  }

  async function runScript(name) {
    const output = $('#script-output');
    const scriptDef = (window._scripts || []).find(function(s) { return s.name === name; });
    let args = '';
    if (scriptDef && /\<[a-zA-Z_]/.test(scriptDef.description || '')) {
      args = prompt('Args for ' + name + '\n' + scriptDef.description, '') || '';
      if (args === null) return;
    }
    output.style.display = 'block';
    output.textContent = 'Running ' + name + (args ? ' ' + args : '') + '...\n';
    try {
      const url = '/api/scripts/' + name + '/run' + (args ? '?args=' + encodeURIComponent(args) : '');
      const r = await fetch(url, { method: 'POST' });
      const body = await r.json();
      if (body.error) {
        output.textContent += 'ERROR: ' + body.error + '\n';
        return;
      }
      const es = new EventSource('/api/scripts/runs/' + body.run_id + '/stream');
      es.onmessage = function(e) {
        output.textContent += e.data + '\n';
        output.scrollTop = output.scrollHeight;
      };
      es.addEventListener('done', function() {
        output.textContent += '\n--- done ---\n';
        es.close();
      });
      es.onerror = function() { es.close(); };
    } catch(e) {
      output.textContent += 'Request failed: ' + e.message + '\n';
    }
  }

  loadScripts();
})();
