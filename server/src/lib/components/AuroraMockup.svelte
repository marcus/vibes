<script>
  // Props
  let { siteTheme = 'dark' } = $props();

  // Window has its own theme that follows the site by default, but can be
  // toggled independently. The effect resyncs it whenever the site theme flips.
  let mockTheme = $state('dark');
  $effect(() => {
    mockTheme = siteTheme;
  });

  const FRIENDS = [
    { handle: "ana",   name: "Ana",    g: ["#f97316", "#fbbf24"], online: true,  status: "rewriting the parser, again", commits: 7, plus: 412, minus: 96,  repos: ["lexer", "docs"], when: "2 min ago",
      spotify: "Starburster · Fontaines D.C.", weather: "Sunny 72°" },
    { handle: "theo",  name: "Theo",   g: ["#34d399", "#0ea5e9"], online: true,  status: "shipping the billing fix...", commits: 4, plus: 188, minus: 240, repos: ["billing"],       when: "just now",
      spotify: null, weather: "Rain 54°" },
    { handle: "priya", name: "Priya",  g: ["#fb7185", "#fdba74"], online: false, status: "",                            commits: 5, plus: 301, minus: 77,  repos: ["api"],           when: "3 hr ago" },
    { handle: "sam",   name: "Sam",    g: ["#60a5fa", "#34d399"], online: false, status: "",                            commits: 0, plus: 0,   minus: 0,   repos: [],                when: "yesterday" },
    { handle: "kofi",  name: "Kofi",   g: ["#facc15", "#fb923c"], online: false, status: "",                            commits: 1, plus: 24,  minus: 3,   repos: ["zine"],          when: "5 hr ago" },
  ];
  const ME = { name: "Marcus", g: ["#2dd4bf", "#1e3a8a"], status: "VIBES", commits: 3, plus: 777, minus: 34, repos: ["braid"],
    spotify: "Pink Pony Club · Chappell Roan", weather: "Cloudy 61°" };

  const online = FRIENDS.filter(f => f.online);
  const offline = FRIENDS.filter(f => !f.online);

  function offSummary(p) {
    return p.commits > 0
      ? `${p.commits} commit${p.commits === 1 ? "" : "s"} · ${p.repos.join(", ")}`
      : "quiet today";
  }

  function toggleMockTheme() {
    mockTheme = mockTheme === 'dark' ? 'light' : 'dark';
  }
</script>

<div class="mac-window d-aurora2 {mockTheme}">
  <div class="titlebar">
    <div class="dots">
      <span class="dot r"></span>
      <span class="dot y"></span>
      <span class="dot g"></span>
    </div>
    <span class="title">Vibes</span>
    <button type="button" class="window-theme-toggle" onclick={toggleMockTheme} aria-label="Toggle mockup theme">
      {#if mockTheme === 'dark'}
        <!-- Sun icon (to switch to light) -->
        <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true">
          <circle cx="12" cy="12" r="5" fill="none" stroke="currentColor" stroke-width="2" />
          <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
        </svg>
      {:else}
        <!-- Moon icon (to switch to dark) -->
        <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true">
          <path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
        </svg>
      {/if}
    </button>
  </div>
  <div class="body">
    <!-- ME card -->
    <div class="card me" style="--c1:{ME.g[0]}; --c2:{ME.g[1]}">
      <div class="row">
        <span class="ring">
          <span class="avatar" style="background: linear-gradient(135deg, {ME.g[0]}, {ME.g[1]})">
            {ME.name[0]}
          </span>
        </span>
        <div class="who">
          <div class="name">you</div>
          <div class="status">{ME.status}</div>
        </div>
        <span class="when">just now</span>
      </div>
      <div class="locbar">
        <div class="add" style="flex-grow:{ME.plus}">+{ME.plus}</div>
        <div class="del" style="flex-grow:{ME.minus}">−{ME.minus}</div>
      </div>
      <div class="legend">
        <span><b>{ME.commits}</b> commit{ME.commits === 1 ? "" : "s"} today</span>
        <span class="repos">{ME.repos.join(", ")}</span>
      </div>
      {#if ME.spotify || ME.weather}
        <div class="extras">
          {#if ME.spotify}
            <span class="track">{ME.spotify}</span>
          {/if}
          {#if ME.weather}
            <span class="wx">{ME.weather}</span>
          {/if}
        </div>
      {/if}
    </div>

    <!-- Friends online cards -->
    {#each online as p}
      <div class="card" style="--c1:{p.g[0]}; --c2:{p.g[1]}">
        <div class="row">
          <span class="ring">
            <span class="avatar" style="background: linear-gradient(135deg, {p.g[0]}, {p.g[1]})">
              {p.name[0]}
            </span>
          </span>
          <div class="who">
            <div class="name">{p.name}</div>
            <div class="status">{p.status}</div>
          </div>
          <span class="when">{p.when}</span>
        </div>
        <div class="locbar">
          <div class="add" style="flex-grow:{p.plus}">+{p.plus}</div>
          <div class="del" style="flex-grow:{p.minus}">−{p.minus}</div>
        </div>
        <div class="legend">
          <span><b>{p.commits}</b> commit{p.commits === 1 ? "" : "s"} today</span>
          <span class="repos">{p.repos.join(", ")}</span>
        </div>
        {#if p.spotify || p.weather}
          <div class="extras">
            {#if p.spotify}
              <span class="track">{p.spotify}</span>
            {/if}
            {#if p.weather}
              <span class="wx">{p.weather}</span>
            {/if}
          </div>
        {/if}
      </div>
    {/each}

    <!-- Away Divider -->
    <div class="divider">Away</div>

    <!-- Friends offline rows -->
    {#each offline as p}
      <div class="off-row" style="--c1:{p.g[0]}; --c2:{p.g[1]}">
        <span class="avatar" style="background: linear-gradient(135deg, {p.g[0]}, {p.g[1]})">
          {p.name[0]}
        </span>
        <span class="name">{p.name}</span>
        <span class="recent">{offSummary(p)}</span>
        <span class="when">{p.when}</span>
      </div>
    {/each}
  </div>
</div>

<style>
  /* Scoped mockup styles, aligned with Vibes tokens.css palette */
  /* Dark palette mirrors the Mac app's VibeColor dark-mode values
     (cool-neutral charcoal, not navy) — see client/Vibes/ContentView.swift. */
  .d-aurora2.dark {
    --bg: #14151a; /* darkBg */
    --bar-bg: #1a1c22; /* chassis */
    --ink: #e9eaf0; /* darkInk */
    --muted: #a7acbd; /* muted */
    --faint: #6c7180; /* faint */
    --card: #2d3035; /* cardSurface */
    --card-border: #43464c; /* cardBorder */
    --me-card: #353a45; /* meCardSurface */
    --me-border: #4c5260; /* meCardBorder */
    --add-bg: #1d3a2b; /* locAddedBg */
    --add-ink: #7fe0a7; /* locAddedInk */
    --del-bg: #3d2526; /* locRemovedBg */
    --del-ink: #f1958b; /* locRemovedInk */
    --divider: #262932; /* sectionDivider */
    --off-bg: rgba(255, 255, 255, .025); /* awayRowSurface */
    --label: #6c7180; /* faint */
  }
  .d-aurora2.light {
    --bg: #f2eee6; /* vibes-paper */
    --bar-bg: #faf8f5;
    --ink: #061320; /* vibes-ink */
    --muted: #6e665b; /* vibes-ash-500 */
    --faint: #a89f92; /* vibes-ash-300 */
    --card: #fdfbf6;
    --card-border: #e7e1d5;
    --me-card: #ece6d8;
    --me-border: #ddd5c2;
    --add-bg: #d9ecdd;
    --add-ink: #1f7a4d;
    --del-bg: #f4ddd6;
    --del-ink: #b3503e;
    --divider: #e4ddcf;
    --off-bg: rgba(255, 255, 255, .45);
    --label: #b3aa99;
  }
  .d-aurora2 {
    background: var(--bg);
    color: var(--ink);
    border-radius: 14px;
    overflow: hidden;
    box-shadow: 0 24px 70px rgba(0,0,0,.3), 0 0 0 .5px rgba(255,255,255,.12);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    text-align: left;
    transition: background 0.2s ease, color 0.2s ease;
    width: 100%;
    max-width: 420px;
    margin: 0 auto;
  }
  .d-aurora2 .titlebar {
    display: flex;
    align-items: center;
    padding: 12px 14px;
    background: var(--bar-bg);
    border-bottom: 1px solid var(--card-border);
    color: var(--ink);
    transition: background 0.2s ease, border-color 0.2s ease;
  }
  .titlebar .dots {
    display: flex;
    gap: 8px;
    width: 52px;
    flex-shrink: 0;
  }
  .titlebar .dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
  }
  .titlebar .dot.r { background: #ff5f57; }
  .titlebar .dot.y { background: #febc2e; }
  .titlebar .dot.g { background: #c8c6c0; }
  
  .titlebar .title {
    flex: 1;
    text-align: center;
    font-size: 13px;
    font-weight: 600;
  }
  
  .titlebar .window-theme-toggle {
    width: 52px;
    flex-shrink: 0;
    display: flex;
    justify-content: flex-end;
    align-items: center;
    background: none;
    border: none;
    cursor: pointer;
    color: var(--faint);
    padding: 0;
    transition: color 0.2s ease;
  }
  .titlebar .window-theme-toggle:hover {
    color: var(--ink);
  }

  .d-aurora2 .body {
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .d-aurora2 .card {
    position: relative;
    border-radius: 18px;
    padding: 15px 16px;
    background: var(--card);
    border: 1px solid var(--card-border);
    overflow: hidden;
    transition: background 0.2s ease, border-color 0.2s ease;
  }
  .d-aurora2 .card.me {
    background: var(--me-card);
    border-color: var(--me-border);
  }
  .d-aurora2 .card .row {
    position: relative;
    display: flex;
    align-items: center;
    gap: 13px;
  }
  .d-aurora2 .card .avatar {
    width: 42px;
    height: 42px;
    font-size: 15px;
  }
  .avatar {
    border-radius: 50%;
    display: grid;
    place-items: center;
    color: #fff;
    font-weight: 700;
    flex: 0 0 auto;
  }
  .d-aurora2 .ring {
    position: relative;
    flex: 0 0 auto;
  }
  .d-aurora2 .ring::after {
    content: "";
    position: absolute;
    inset: -4px;
    border-radius: 50%;
    border: 2px solid var(--c1);
    opacity: .6;
    animation: breathe 3.4s ease-in-out infinite;
  }
  @keyframes breathe {
    0%, 100% { transform: scale(1); opacity: .6; }
    50%      { transform: scale(1.09); opacity: .2; }
  }
  .d-aurora2 .card .who {
    flex: 1;
    min-width: 0;
  }
  .d-aurora2 .card .name {
    font-size: 15px;
    font-weight: 700;
  }
  .d-aurora2 .card .status {
    font-size: 12.5px;
    color: var(--muted);
    margin-top: 2px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .d-aurora2 .when {
    font-size: 11px;
    color: var(--faint);
    white-space: nowrap;
    align-self: flex-start;
    margin-top: 2px;
  }

  /* full-width add/remove bar: additions left, deletions right, numbers inside */
  .d-aurora2 .locbar {
    position: relative;
    display: flex;
    margin-top: 13px;
    height: 22px;
    border-radius: 99px;
    overflow: hidden;
    font-size: 11px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .d-aurora2 .locbar .add {
    flex: 1 1 0;
    min-width: 64px;
    background: var(--add-bg);
    color: var(--add-ink);
    display: flex;
    align-items: center;
    padding: 0 12px;
  }
  .d-aurora2 .locbar .del {
    flex: 1 1 0;
    min-width: 64px;
    background: var(--del-bg);
    color: var(--del-ink);
    display: flex;
    align-items: center;
    justify-content: flex-end;
    padding: 0 12px;
  }
  .d-aurora2 .legend {
    position: relative;
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-top: 9px;
    font-size: 11.5px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .d-aurora2 .legend b {
    color: var(--ink);
    font-weight: 700;
  }
  .d-aurora2 .legend .repos {
    color: var(--faint);
    font-weight: 600;
  }

  /* spotify + weather: one quiet line, faint tier, never competes with stats */
  .d-aurora2 .extras {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 12px;
    margin-top: 8px;
    font-size: 11.5px;
    color: var(--faint);
    font-variant-numeric: tabular-nums;
  }
  .d-aurora2 .extras .track {
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .d-aurora2 .extras .track::before {
    content: "♪ ";
    opacity: .8;
  }
  .d-aurora2 .extras .wx {
    flex: 0 0 auto;
    margin-left: auto;
    white-space: nowrap;
  }

  .d-aurora2 .divider {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 8px 2px 0;
    font-size: 10.5px;
    font-weight: 700;
    letter-spacing: .1em;
    text-transform: uppercase;
    color: var(--label);
  }
  .d-aurora2 .divider::after {
    content: "";
    flex: 1;
    height: 1px;
    background: var(--divider);
  }
  .d-aurora2 .off-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 7px 10px;
    border-radius: 11px;
    background: var(--off-bg);
    transition: background 0.2s ease;
  }
  .d-aurora2 .off-row .avatar {
    width: 26px;
    height: 26px;
    font-size: 10px;
    filter: saturate(.3) brightness(.9);
  }
  .d-aurora2 .off-row .name {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--muted);
  }
  .d-aurora2 .off-row .recent {
    flex: 1;
    font-size: 11.5px;
    color: var(--faint);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    text-align: left;
  }
  .d-aurora2 .off-row .when {
    font-size: 11px;
    color: var(--faint);
  }
</style>
