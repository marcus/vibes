<script>
  // Interactive mockup of the Vibes Mac app (orbit redesign, 0.5.0).
  // Mirrors client/Vibes/OrbitView.swift: orb size = today's churn, ring =
  // today vs that person's typical day (green adds / red deletes, gold lap
  // badge past 1×), repo "moons", offline friends drifting along the bottom.
  let { siteTheme = 'dark' } = $props();

  // Window theme follows the site by default but can be toggled independently.
  let mockTheme = $state('dark');
  $effect(() => {
    mockTheme = siteTheme;
  });

  // The header capsule actually switches views, like the app.
  let view = $state('orbit');

  // sweep/green are conic-gradient degrees: sweep = today vs typical day,
  // green = the adds share of the swept arc.
  const ORBS = [
    {
      name: 'dana', g: ['#ff7847', '#ff4787'], size: 84, x: 30, y: 26,
      sweep: 360, green: 230, lap: '1.7×',
      status: 'deep in the parser mines', plus: '+1,204', minus: '−688',
      commits: 14, repos: ['perch', 'perch-docs'], when: '2m', float: 7
    },
    {
      name: 'priya', g: ['#27d3a2', '#1f9bff'], size: 74, x: 71, y: 32,
      sweep: 311, green: 50, lap: null,
      status: 'refactor friday!!', plus: '+356', minus: '−1,892',
      commits: 7, repos: ['atlas'], when: '8m', float: 9
    },
    {
      name: 'you', initial: 'M', me: true, g: ['#4f8cff', '#9b5cff'], size: 64, x: 48, y: 64,
      sweep: 274, green: 217, lap: null,
      status: 'shipping the orbit view ✨', plus: '+482', minus: '−127',
      commits: 9, repos: ['vibes', 'td-watch'], when: 'now', float: 8
    }
  ];

  const DRIFTERS = [
    { name: 'sam', g: ['#8a94a6', '#5b6472'], detail: '2h · +210 −95 in kiln' },
    { name: 'kei', g: ['#b08cff', '#7a5cd0'], detail: '1d' }
  ];

  // Stable per-repo dot hue, mirroring the app's djb2 hash.
  function repoHue(alias) {
    let h = 5381 >>> 0;
    for (const ch of alias) h = ((h * 33) >>> 0) + ch.codePointAt(0);
    return h % 360;
  }

  function toggleMockTheme() {
    mockTheme = mockTheme === 'dark' ? 'light' : 'dark';
  }
</script>

<div class="mac-window d-orbit {mockTheme}">
  <!-- Titlebar: lights, wordmark, and controls share one band, like the app -->
  <div class="titlebar">
    <div class="dots">
      <span class="dot r"></span>
      <span class="dot y"></span>
      <span class="dot g"></span>
    </div>
    <span class="wordmark">vibes</span>
    <span class="grow"></span>
    <div class="seg" role="tablist" aria-label="Feed view">
      <button type="button" class:active={view === 'orbit'} onclick={() => (view = 'orbit')}>
        ✦ orbit
      </button>
      <button type="button" class:active={view === 'list'} onclick={() => (view = 'list')}>
        ☰ list
      </button>
    </div>
    <span class="presence" title="Online — click to go offline"><i></i></span>
    <button type="button" class="window-theme-toggle" onclick={toggleMockTheme} aria-label="Toggle mockup theme">
      {#if mockTheme === 'dark'}
        <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true">
          <circle cx="12" cy="12" r="5" fill="none" stroke="currentColor" stroke-width="2" />
          <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
        </svg>
      {:else}
        <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true">
          <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
        </svg>
      {/if}
    </button>
  </div>

  {#if view === 'orbit'}
    <!-- ── Orbit sky ── -->
    <div class="sky">
      {#each ORBS as p}
        <div
          class="orb"
          style="left:{p.x}%; top:{p.y}%; --float:{p.float}s;"
        >
          <div
            class="globe"
            style="
              width:{p.size}px; height:{p.size}px;
              background:linear-gradient(135deg, {p.g[0]}, {p.g[1]});
              --glow:{p.g[0]};
              --sweep:{p.sweep}deg; --green:{p.green}deg;
              font-size:{Math.round(p.size * 0.3)}px;
            "
          >
            {(p.initial ?? p.name[0]).toUpperCase()}
            {#if p.lap}<span class="lap">{p.lap}</span>{/if}
          </div>
          {#if p.repos[0]}
            <span class="moon m1" style="--mc:hsl({repoHue(p.repos[0])} 55% 65%)">{p.repos[0]}</span>
          {/if}
          {#if p.repos[1]}
            <span class="moon m2" style="--mc:hsl({repoHue(p.repos[1])} 55% 65%)">{p.repos[1]}</span>
          {/if}
          <div class="tag">{p.name}</div>
          <div class="note">{p.status}</div>
          <div class="loc"><b class="p">{p.plus}</b> <b class="m">{p.minus}</b> · {p.commits}c</div>
        </div>
      {/each}
    </div>

    <!-- ── Drifting dock ── -->
    <div class="drift">
      <span class="label">Drifting</span>
      {#each DRIFTERS as d}
        <span class="drifter">
          <span class="mini" style="background:linear-gradient(135deg, {d.g[0]}, {d.g[1]})"></span>
          <b>{d.name}</b>
          <em>{d.detail}</em>
        </span>
      {/each}
    </div>
  {:else}
    <!-- ── List fallback ── -->
    <div class="list">
      {#each ORBS as p}
        <div class="card" class:me={p.me}>
          <div class="row">
            <span class="ring"><span class="avatar" style="background:linear-gradient(135deg, {p.g[0]}, {p.g[1]})">{(p.initial ?? p.name[0]).toUpperCase()}</span></span>
            <div class="who">
              <div class="name">{p.name}</div>
              <div class="status">{p.status}</div>
            </div>
            <span class="when">{p.when}</span>
          </div>
          <div class="diff">
            <b class="p">{p.plus}</b>
            <span class="diffbar"><i class="dg" style="flex-grow:{p.green}"></i><i class="dr" style="flex-grow:{Math.max(p.sweep - p.green, 8)}"></i></span>
            <b class="m">{p.minus}</b>
          </div>
        </div>
      {/each}
      <div class="divider">Away</div>
      {#each DRIFTERS as d}
        <div class="off-row">
          <span class="mini" style="background:linear-gradient(135deg, {d.g[0]}, {d.g[1]})"></span>
          <b>{d.name}</b>
          <em>{d.detail}</em>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .d-orbit.dark {
    --bg: #0e1018;
    --bg-glow-a: rgba(64, 141, 255, 0.10);
    --bg-glow-b: rgba(167, 93, 255, 0.09);
    --ink: rgba(255, 255, 255, 0.92);
    --muted: rgba(255, 255, 255, 0.55);
    --faint: rgba(255, 255, 255, 0.32);
    --chip: rgba(255, 255, 255, 0.08);
    --chip-border: rgba(255, 255, 255, 0.10);
    --seg-bg: rgba(255, 255, 255, 0.08);
    --seg-active: rgba(255, 255, 255, 0.16);
    --track: rgba(255, 255, 255, 0.12);
    --card: rgba(255, 255, 255, 0.05);
    --card-border: rgba(255, 255, 255, 0.08);
    --band: rgba(255, 255, 255, 0.04);
    --plus: #4ade80;
    --minus: #fb7185;
    --gold: #fbbf24;
    --glow-opacity: 0.45;
  }
  .d-orbit.light {
    --bg: #f4f1ea;
    --bg-glow-a: rgba(64, 141, 255, 0.10);
    --bg-glow-b: rgba(167, 93, 255, 0.08);
    --ink: #1c2330;
    --muted: #6e665b;
    --faint: #a89f92;
    --chip: rgba(0, 0, 0, 0.05);
    --chip-border: rgba(0, 0, 0, 0.08);
    --seg-bg: rgba(0, 0, 0, 0.06);
    --seg-active: rgba(255, 255, 255, 0.85);
    --track: rgba(0, 0, 0, 0.10);
    --card: rgba(255, 255, 255, 0.65);
    --card-border: rgba(0, 0, 0, 0.07);
    --band: rgba(0, 0, 0, 0.035);
    --plus: #1f9a52;
    --minus: #d6455c;
    --gold: #b07c0a;
    --glow-opacity: 0.30;
  }

  .d-orbit {
    position: relative;
    width: 100%;
    max-width: 440px;
    margin: 0 auto;
    border-radius: 16px;
    overflow: hidden;
    background:
      radial-gradient(420px 280px at 72% -8%, var(--bg-glow-a), transparent 60%),
      radial-gradient(360px 300px at 8% 108%, var(--bg-glow-b), transparent 60%),
      var(--bg);
    color: var(--ink);
    box-shadow: 0 24px 70px rgba(0, 0, 0, 0.3), 0 0 0 0.5px rgba(255, 255, 255, 0.12);
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
    text-align: left;
    transition: background 0.2s ease, color 0.2s ease;
  }

  /* ── titlebar: one band shared by lights, wordmark, and controls ── */
  .titlebar {
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 13px 14px 11px;
  }
  .dots { display: flex; gap: 7px; margin-right: 4px; flex-shrink: 0; }
  .dot { width: 12px; height: 12px; border-radius: 50%; }
  .dot.r { background: #ff5f57; }
  .dot.y { background: #febc2e; }
  .dot.g { background: #28c840; }
  .wordmark { font-size: 16px; font-weight: 300; letter-spacing: 0.01em; }
  .grow { flex: 1; }

  .seg {
    display: flex; gap: 2px; padding: 3px; border-radius: 99px;
    background: var(--seg-bg); border: 1px solid var(--chip-border);
  }
  .seg button {
    border: 0; background: none; cursor: pointer; color: var(--muted);
    font: 500 10.5px -apple-system, BlinkMacSystemFont, sans-serif;
    padding: 3px 9px; border-radius: 99px; transition: color 0.15s, background 0.15s;
  }
  .seg button.active { background: var(--seg-active); color: var(--ink); }

  .presence {
    display: grid; place-items: center; width: 26px; height: 22px;
    border-radius: 99px; background: var(--seg-bg); border: 1px solid var(--chip-border);
  }
  .presence i {
    width: 8px; height: 8px; border-radius: 50%;
    background: #30d158; box-shadow: 0 0 6px rgba(48, 209, 88, 0.7);
  }

  .window-theme-toggle {
    background: none; border: none; cursor: pointer; color: var(--faint);
    padding: 0 0 0 2px; display: flex; align-items: center; transition: color 0.2s ease;
  }
  .window-theme-toggle:hover { color: var(--ink); }

  /* ── orbit sky ── */
  .sky { position: relative; height: 430px; }
  .orb {
    position: absolute;
    transform: translateX(-50%);
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    width: 150px;
    animation: float var(--float) ease-in-out infinite;
  }
  @keyframes float {
    0%, 100% { margin-top: 0; }
    50% { margin-top: -8px; }
  }
  .globe {
    position: relative; border-radius: 50%;
    display: grid; place-items: center;
    color: rgba(255, 255, 255, 0.95); font-weight: 700;
    box-shadow: 0 0 30px color-mix(in srgb, var(--glow) calc(var(--glow-opacity) * 100%), transparent),
      inset 0 -8px 16px rgba(0, 0, 0, 0.25);
    margin-bottom: 7px;
  }
  /* churn ring: green adds → red deletes → faint remainder of the day */
  .globe::before {
    content: ''; position: absolute; inset: -7px; border-radius: 50%;
    background: conic-gradient(#4ade80 0 var(--green), #fb7185 var(--green) var(--sweep), var(--track) var(--sweep));
    -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 3.5px), #000 calc(100% - 3px));
    mask: radial-gradient(farthest-side, transparent calc(100% - 3.5px), #000 calc(100% - 3px));
  }
  .lap {
    position: absolute; top: -11px; right: -16px;
    padding: 1px 6px; border-radius: 99px;
    background: color-mix(in srgb, var(--gold) 16%, transparent);
    border: 1px solid color-mix(in srgb, var(--gold) 45%, transparent);
    color: var(--gold);
    font: 700 9.5px ui-monospace, 'SF Mono', monospace;
  }
  .moon {
    position: absolute;
    padding: 2px 7px; border-radius: 99px;
    background: var(--chip); border: 1px solid var(--chip-border);
    color: var(--muted); font-size: 9.5px; white-space: nowrap;
  }
  .moon::before {
    content: ''; display: inline-block; width: 5px; height: 5px;
    border-radius: 50%; background: var(--mc); margin-right: 4px; vertical-align: 0.5px;
  }
  .moon.m1 { top: -4%; left: 62%; }
  .moon.m2 { top: 48%; right: 64%; }
  .tag { font-size: 12px; font-weight: 600; }
  .note {
    max-width: 150px; font-size: 10.5px; color: var(--muted);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .loc { font: 600 10px ui-monospace, 'SF Mono', monospace; color: var(--faint); }
  .loc .p { color: var(--plus); }
  .loc .m { color: var(--minus); }

  /* ── drifting dock ── */
  .drift {
    display: flex; align-items: center; gap: 14px;
    padding: 10px 16px 13px;
    border-top: 1px solid var(--card-border);
    background: var(--band);
    overflow: hidden; white-space: nowrap;
  }
  .drift .label {
    font-size: 9.5px; font-weight: 700; letter-spacing: 0.12em;
    text-transform: uppercase; color: var(--faint);
  }
  .drifter { display: inline-flex; align-items: center; gap: 6px; opacity: 0.75; }
  .mini { width: 18px; height: 18px; border-radius: 50%; flex: 0 0 auto; filter: saturate(0.4); }
  .drifter b, .off-row b { font-size: 11px; font-weight: 600; color: var(--muted); }
  .drifter em, .off-row em {
    font-style: normal; font-size: 10px; color: var(--faint);
    font-variant-numeric: tabular-nums;
  }

  /* ── list fallback ── */
  .list { padding: 4px 14px 16px; display: flex; flex-direction: column; gap: 8px; min-height: 462px; }
  .card {
    border-radius: 13px; padding: 11px 13px;
    background: var(--card); border: 1px solid var(--card-border);
  }
  .card.me { background: color-mix(in srgb, #4f8cff 9%, var(--card)); border-color: color-mix(in srgb, #4f8cff 25%, var(--card-border)); }
  .card .row { display: flex; align-items: center; gap: 10px; }
  .ring { position: relative; flex: 0 0 auto; }
  .ring::after {
    content: ''; position: absolute; inset: -4px; border-radius: 50%;
    border: 2px solid #30d158; opacity: 0.7;
    animation: breathe 3.4s ease-in-out infinite;
  }
  @keyframes breathe {
    0%, 100% { transform: scale(1); opacity: 0.7; }
    50% { transform: scale(1.09); opacity: 0.25; }
  }
  .avatar {
    width: 34px; height: 34px; border-radius: 50%;
    display: grid; place-items: center;
    color: #fff; font-weight: 700; font-size: 13px;
  }
  .who { flex: 1; min-width: 0; }
  .name { font-size: 13px; font-weight: 600; }
  .status {
    font-size: 11px; color: var(--muted);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .when { font-size: 10px; color: var(--faint); align-self: flex-start; }
  .diff { display: flex; align-items: center; gap: 8px; margin-top: 10px; }
  .diff b { font: 600 10.5px ui-monospace, 'SF Mono', monospace; }
  .diff .p { color: var(--plus); }
  .diff .m { color: var(--minus); }
  .diffbar { flex: 1; display: flex; height: 6px; border-radius: 3px; overflow: hidden; background: var(--track); }
  .diffbar .dg { background: linear-gradient(90deg, #23b14d, #4ade80); }
  .diffbar .dr { background: linear-gradient(90deg, #fb7185, #e0443a); }
  .divider {
    display: flex; align-items: center; gap: 10px; margin: 6px 2px 0;
    font-size: 9.5px; font-weight: 700; letter-spacing: 0.12em;
    text-transform: uppercase; color: var(--faint);
  }
  .divider::after { content: ''; flex: 1; height: 1px; background: var(--card-border); }
  .off-row { display: flex; align-items: center; gap: 8px; padding: 5px 4px; }
</style>
