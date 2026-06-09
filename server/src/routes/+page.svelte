<script>
  import { onMount } from 'svelte';
  import AuroraMockup from '$lib/components/AuroraMockup.svelte';

  let theme = $state('dark'); // Default to dark for SSR/initial load

  onMount(() => {
    const currentTheme = document.documentElement.getAttribute('data-theme') ||
      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    theme = currentTheme;
  });

  function toggleTheme() {
    theme = theme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem('theme', theme);
    } catch (e) {}
  }
</script>

<svelte:head>
  <title>Vibes — See who's coding right now</title>
  <meta
    name="description"
    content="See which friends are online and coding — private ambient presence for small groups of coders on macOS."
  />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link
    href="https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600;700;800&display=swap"
    rel="stylesheet"
  />
</svelte:head>

<div class="home">
  <!-- Animated aurora backdrop -->
  <div class="aurora" aria-hidden="true">
    <span class="a1"></span><span class="a2"></span><span class="a3"></span><span class="a4"></span>
  </div>
  <div class="grain" aria-hidden="true"></div>

  <!-- ===================== NAV ===================== -->
  <nav class="nav">
    <a class="brand" href="#top" aria-label="Vibes home">
      <img class="mark" src="/images/vibes-icon.png" srcset="/images/vibes-icon.png 1x, /images/vibes-icon@2x.png 2x" width="30" height="30" alt="" />
      <span class="word">Vibes</span>
    </a>
    <div class="nav-spacer"></div>
    <button
      type="button"
      class="theme-toggle"
      onclick={toggleTheme}
      aria-label={theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'}
      title="Toggle theme"
    >
      {#if theme === 'dark'}
        <svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
      {:else}
        <svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>
      {/if}
    </button>
    <a class="btn btn-primary nav-cta" href="/download">Download</a>
  </nav>

  <main id="top">
    <!-- ===================== HERO ===================== -->
    <section class="hero shell">
      <div class="eyebrow"><span class="pip"></span> Now coding · 3 friends online</div>
      <h1>See who's <span class="spectrum-text">coding</span><br />right now.</h1>
      <p class="hero-sub">Vibes shows which friends are online and how much they've coded today.</p>
      <p class="hero-lede">A Mac app for small groups. It turns your local Git activity into a simple, private friend feed.</p>
      <div class="hero-cta">
        <a class="btn btn-primary" href="/download">
          <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
          Download for Mac
        </a>
      </div>
      <p class="hero-fine">For Apple Silicon · macOS 26</p>

      <div class="privacy">
        <svg class="lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
        <span><b>Shares aggregate activity only.</b> No repo paths, branches, commit messages, filenames, editor activity, process history, or transcripts.</span>
      </div>
    </section>

    <!-- ===================== MOCKUP ===================== -->
    <section class="stage shell">
      <div class="window-wrap">
        <AuroraMockup siteTheme={theme} />
      </div>
      <p class="stage-cap">Interactive mockup of the Vibes Mac app. <b>Try toggling light and dark mode</b> on the window or website.</p>
    </section>

    <!-- ===================== GET STARTED ===================== -->
    <section class="getstarted shell">
      <div class="section-head">
        <div class="section-eyebrow">Get started</div>
        <h2>Bring your group online.</h2>
      </div>
      <div class="steps">
        <div class="step">
          <div class="step-num">01</div>
          <h3>Install</h3>
          <p>Download and install Vibes for macOS.</p>
        </div>
        <div class="step">
          <div class="step-num">02</div>
          <h3>Name yourself</h3>
          <p>Open it and enter a display name.</p>
        </div>
        <div class="step">
          <div class="step-num">03</div>
          <h3>Add friends</h3>
          <p>Tap Add Friend to send a one-time invite link, or accept one you were sent.</p>
        </div>
        <div class="step">
          <div class="step-num">04</div>
          <h3>Add your repos</h3>
          <p>You're online while you're coding, and one tap takes you offline.</p>
        </div>
      </div>
    </section>

    <!-- ===================== CTA ===================== -->
    <section class="cta-strip shell">
      <h2>Code together, <span class="spectrum-text">apart.</span></h2>
      <p>Small groups, private by design. Bring your friends online.</p>
      <a class="btn btn-primary" href="/download">
        <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
        Download for Mac
      </a>
    </section>
  </main>

  <!-- ===================== FOOTER ===================== -->
  <footer class="footer">
    <div class="shell footer-in">
      <a class="brand" href="#top">
        <img class="mark" src="/images/vibes-icon.png" srcset="/images/vibes-icon.png 1x, /images/vibes-icon@2x.png 2x" width="24" height="24" alt="" />
        <span class="word">Vibes</span>
      </a>
      <div class="nav-spacer"></div>
      <div class="footer-links">
        <a href="/download">Download</a>
        <a href="#top">Privacy</a>
        <a href="#top">Made for friends</a>
      </div>
      <span class="footer-copy">© Vibes 2026</span>
    </div>
  </footer>
</div>

<style>
  /* ============================================================
     VIBES homepage — neon spectrum redesign.
     All tokens are scoped to .home so the rest of the app
     (admin, download, invite) keeps its own token system.
     ============================================================ */
  .home {
    /* ---- Brand neon spectrum ---- */
    --v-pink: #ff4d8d;
    --v-orange: #ff7a3d;
    --v-cyan: #45d4ff;
    --v-violet: #a472ff;

    --grad-spectrum: linear-gradient(105deg,
      #a472ff 0%, #ff4d8d 30%, #ff7a3d 54%,
      #ff5e7e 66%, #45d4ff 86%, #6f8cff 100%);
    --grad-btn: linear-gradient(105deg,
      #7d3ce6 0%, #d62a72 32%, #d6602a 56%,
      #c83a8e 70%, #2f6ae0 100%);

    --green-500: #43d17f;

    /* ---- Type ---- */
    --font: "Geist", -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
    --t-xs: 12px; --t-sm: 13px; --t-md: 14px; --t-base: 15px; --t-lg: 17px;
    --t-xl: 20px; --t-2xl: 24px; --t-3xl: 30px; --t-4xl: 40px; --t-5xl: 56px;
    --t-6xl: 76px; --t-7xl: 96px;

    /* ---- Spacing ---- */
    --s-1: 4px; --s-2: 8px; --s-3: 12px; --s-4: 16px; --s-5: 20px; --s-6: 24px;
    --s-7: 32px; --s-8: 40px; --s-9: 48px; --s-10: 64px; --s-11: 80px;
    --s-12: 96px; --s-13: 128px;

    /* ---- Radii ---- */
    --r-sm: 6px; --r-md: 9px; --r-lg: 14px; --r-full: 9999px;

    /* ---- Motion ---- */
    --dur-fast: 180ms; --dur-normal: 260ms; --dur-slow: 420ms;
    --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
    --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
    --ease-spring: cubic-bezier(0.34, 1.4, 0.5, 1);

    /* ---- Dark semantic (default) ---- */
    --bg-base: #060709;
    --bg-secondary: #101113;
    --bg-tertiary: #15171a;
    --bg-glass: rgba(14, 15, 17, 0.66);
    --text-primary: #f4f6f8;
    --text-secondary: #b1b6bf;
    --text-tertiary: #80858f;
    --text-quaternary: #595d66;
    --border-strong: #2c2f36;
    --border-default: #212329;
    --border-subtle: #17181c;
    --accent-default: var(--v-pink);
    --status-online: var(--green-500);
    --aurora-opacity: 0.55;

    min-height: 100vh;
    background: var(--bg-base);
    color: var(--text-primary);
    font-family: var(--font);
    font-size: var(--t-md);
    line-height: 1.5;
    letter-spacing: -0.011em;
    font-feature-settings: "ss01", "cv01";
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    transition: background var(--dur-normal) var(--ease-out), color var(--dur-normal) var(--ease-out);
    position: relative;
    overflow: clip;
  }

  /* ---- Light semantic ---- */
  :global(html[data-theme="light"]) .home {
    --bg-base: #f4f5f8;
    --bg-secondary: #fbfbfd;
    --bg-tertiary: #f2f3f6;
    --bg-glass: rgba(255, 255, 255, 0.72);
    --text-primary: #14151a;
    --text-secondary: #44474f;
    --text-tertiary: #6c707a;
    --text-quaternary: #9aa0aa;
    --border-strong: #d6dae1;
    --border-default: #e4e7ec;
    --border-subtle: #eef0f3;
    --accent-default: #ff2d7e;
    --status-online: #1fb866;
    --aurora-opacity: 0.38;
  }

  .home :global(::selection) { background: rgba(255, 77, 141, 0.28); color: var(--text-primary); }

  .home h1, .home h2, .home h3 {
    font-family: var(--font);
    font-weight: 700;
    line-height: 1.05;
    letter-spacing: -0.022em;
    color: var(--text-primary);
    margin: 0;
    text-wrap: balance;
  }
  .home p { margin: 0; }
  .home a { color: inherit; text-decoration: none; }

  .spectrum-text {
    background: var(--grad-spectrum);
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
  }

  /* ---- Aurora backdrop ---- */
  .aurora {
    position: absolute; inset: -25%; z-index: 0;
    pointer-events: none; opacity: var(--aurora-opacity);
    filter: blur(70px) saturate(1.25);
    transition: opacity var(--dur-slow) var(--ease-out);
  }
  .aurora span {
    position: absolute; width: 50vw; height: 50vw;
    border-radius: var(--r-full); mix-blend-mode: screen; will-change: transform;
  }
  :global(html[data-theme="light"]) .aurora span { mix-blend-mode: multiply; opacity: 0.6; }
  .aurora .a1 { background: radial-gradient(circle, var(--v-pink), transparent 65%);   top: -8%; left: 4%;  animation: drift1 24s var(--ease-in-out) infinite; }
  .aurora .a2 { background: radial-gradient(circle, var(--v-cyan), transparent 65%);   top: -4%; right: 2%; animation: drift2 28s var(--ease-in-out) infinite; }
  .aurora .a3 { background: radial-gradient(circle, var(--v-orange), transparent 65%); top: 24%; left: 30%; animation: drift3 32s var(--ease-in-out) infinite; }
  .aurora .a4 { background: radial-gradient(circle, var(--v-violet), transparent 68%); top: 40%; right: 22%; animation: drift1 30s var(--ease-in-out) infinite reverse; }

  @keyframes drift1 { 0%,100%{ transform: translate(0,0) scale(1);} 50%{ transform: translate(8vw,6vh) scale(1.18);} }
  @keyframes drift2 { 0%,100%{ transform: translate(0,0) scale(1.1);} 50%{ transform: translate(-7vw,8vh) scale(.9);} }
  @keyframes drift3 { 0%,100%{ transform: translate(0,0) scale(.95);} 50%{ transform: translate(5vw,-7vh) scale(1.2);} }

  .grain {
    position: absolute; inset: 0; z-index: 0; pointer-events: none;
    opacity: 0.035; mix-blend-mode: overlay;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='3'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  }

  /* ---- Layout shell ---- */
  .shell { position: relative; z-index: 1; max-width: 1120px; margin: 0 auto; padding: 0 var(--s-6); }

  /* ---- Nav ---- */
  .nav {
    position: sticky; top: 0; z-index: 50;
    display: flex; align-items: center; gap: var(--s-4);
    height: 64px; padding: 0 var(--s-6);
    background: var(--bg-glass);
    backdrop-filter: saturate(1.6) blur(16px);
    -webkit-backdrop-filter: saturate(1.6) blur(16px);
    border-bottom: 1px solid var(--border-subtle);
  }
  .brand { display: flex; align-items: center; gap: var(--s-3); }
  .brand .mark {
    width: 30px; height: 30px; display: block; border-radius: 8px;
    filter: drop-shadow(0 0 10px rgba(255,77,141,.35));
  }
  .footer .brand .mark { width: 24px; height: 24px; border-radius: 6px; }
  .brand .word {
    font-size: var(--t-lg); font-weight: 700;
    letter-spacing: -0.022em; color: var(--text-primary);
  }
  .nav-spacer { flex: 1; }

  .theme-toggle {
    display: inline-flex; align-items: center; justify-content: center;
    width: 38px; height: 38px; border-radius: var(--r-full);
    background: var(--bg-tertiary); border: 1px solid var(--border-default);
    color: var(--text-secondary); cursor: pointer;
    transition: color var(--dur-fast) var(--ease-out), border-color var(--dur-fast) var(--ease-out), transform var(--dur-fast) var(--ease-out);
  }
  .theme-toggle:hover { color: var(--text-primary); border-color: var(--border-strong); transform: translateY(-1px); }
  .theme-toggle svg { width: 17px; height: 17px; }

  /* ---- Buttons ---- */
  .btn {
    display: inline-flex; align-items: center; gap: var(--s-2);
    height: 44px; padding: 0 var(--s-5);
    font-family: var(--font); font-size: var(--t-base);
    font-weight: 600; letter-spacing: -0.01em;
    border-radius: var(--r-full); border: 1px solid transparent;
    cursor: pointer; white-space: nowrap;
  }
  .btn-primary {
    position: relative; color: #fff; border: none;
    background: var(--grad-btn);
    background-size: 160% 160%; background-position: 0% 50%;
    text-shadow: 0 1px 2px rgba(0,0,0,0.22);
    box-shadow: 0 6px 22px -6px rgba(214,42,114,.5), 0 0 0 1px rgba(255,255,255,.06) inset;
    transition: background-position var(--dur-slow) var(--ease-out),
                transform var(--dur-fast) var(--ease-spring),
                box-shadow var(--dur-fast) var(--ease-out);
  }
  .btn-primary:hover { background-position: 100% 50%; transform: translateY(-2px); box-shadow: 0 12px 34px -6px rgba(110,140,255,.6), 0 0 0 1px rgba(255,255,255,.1) inset; }
  .btn-primary:active { transform: translateY(0); }
  .btn-primary .apple { width: 17px; height: 17px; margin-top: -2px; }
  .nav-cta { height: 38px; padding: 0 18px; font-size: var(--t-md); }

  /* ---- Hero ---- */
  .hero { padding: var(--s-13) 0 var(--s-10); text-align: center; }
  .eyebrow {
    display: inline-flex; align-items: center; gap: var(--s-2);
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--text-tertiary); margin-bottom: var(--s-6);
  }
  .eyebrow .pip { width: 7px; height: 7px; border-radius: 50%; background: var(--status-online);
    box-shadow: 0 0 10px var(--status-online); animation: breathe 2.6s var(--ease-in-out) infinite; }
  @keyframes breathe { 0%,100%{ opacity:1; transform: scale(1);} 50%{ opacity:.55; transform: scale(.8);} }

  .hero h1 {
    font-size: clamp(44px, 7.4vw, var(--t-7xl));
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 1.0;
  }
  .hero-sub {
    max-width: 620px; margin: var(--s-6) auto 0;
    font-size: clamp(17px, 2.2vw, var(--t-xl));
    color: var(--text-secondary); line-height: 1.25; font-weight: 400;
  }
  .hero-lede {
    max-width: 560px; margin: var(--s-4) auto 0;
    font-size: var(--t-base); color: var(--text-secondary); line-height: 1.62;
  }
  .hero-cta { display: flex; gap: var(--s-3); justify-content: center; align-items: center; margin-top: var(--s-8); flex-wrap: wrap; }
  .hero-fine { margin-top: var(--s-3); font-size: var(--t-xs); color: var(--text-tertiary); }

  /* Privacy line */
  .privacy {
    display: inline-flex; align-items: center; gap: var(--s-3);
    max-width: 700px; margin: var(--s-9) auto 0;
    padding: var(--s-3) var(--s-5);
    font-size: var(--t-md); color: var(--text-secondary);
    line-height: 1.25; text-align: left;
    background: var(--bg-secondary); border: 1px solid var(--border-subtle);
    border-radius: var(--r-full);
  }
  .privacy .lock { flex-shrink: 0; width: 16px; height: 16px; color: var(--v-cyan); }
  .privacy b { color: var(--text-primary); font-weight: 600; }

  /* ---- Mockup stage ---- */
  .stage { padding: var(--s-9) 0 var(--s-12); }
  .window-wrap { perspective: 2000px; }
  .stage-cap { text-align: center; margin-top: var(--s-6); font-size: var(--t-sm); color: var(--text-tertiary); }
  .stage-cap b { color: var(--text-secondary); font-weight: 500; }

  /* ---- Get started ---- */
  .getstarted { padding: var(--s-12) 0; }
  .section-head { text-align: center; margin-bottom: var(--s-10); }
  .section-eyebrow {
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--accent-default); margin-bottom: var(--s-3);
  }
  .section-head h2 { font-size: clamp(30px, 4.4vw, var(--t-5xl)); font-weight: 800; letter-spacing: -0.022em; }

  .steps { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--s-4); }
  .step {
    position: relative; padding: var(--s-6);
    background: var(--bg-secondary); border: 1px solid var(--border-subtle);
    border-radius: var(--r-lg); overflow: hidden;
    transition: transform var(--dur-normal) var(--ease-out), border-color var(--dur-normal) var(--ease-out);
  }
  .step::before {
    content: ""; position: absolute; inset: 0 0 auto 0; height: 2px;
    background: var(--grad-spectrum); opacity: 0; transition: opacity var(--dur-normal) var(--ease-out);
  }
  .step:hover { transform: translateY(-4px); border-color: var(--border-strong); }
  .step:hover::before { opacity: 1; }
  .step-num {
    font-size: var(--t-2xl); font-weight: 800;
    letter-spacing: -0.04em; line-height: 1;
    background: var(--grad-spectrum); -webkit-background-clip: text; background-clip: text; color: transparent;
    margin-bottom: var(--s-4);
  }
  .step h3 { font-size: var(--t-lg); font-weight: 700; margin-bottom: var(--s-2); letter-spacing: -0.015em; }
  .step p { font-size: var(--t-sm); color: var(--text-tertiary); line-height: 1.25; }

  /* ---- CTA strip ---- */
  .cta-strip { text-align: center; padding: var(--s-10) 0 var(--s-13); }
  .cta-strip h2 { font-size: clamp(28px, 4vw, var(--t-4xl)); font-weight: 800; letter-spacing: -0.022em; }
  .cta-strip p { margin: var(--s-3) auto var(--s-7); color: var(--text-tertiary); max-width: 440px; }

  /* ---- Footer ---- */
  .footer { position: relative; z-index: 1; border-top: 1px solid var(--border-subtle); padding: var(--s-8) 0; }
  .footer-in { display: flex; align-items: center; gap: var(--s-5); flex-wrap: wrap; }
  .footer .brand .word { font-size: var(--t-md); }
  .footer-links { display: flex; gap: var(--s-5); flex-wrap: wrap; }
  .footer-links a { color: var(--text-tertiary); font-size: var(--t-sm); font-weight: 500; transition: color var(--dur-fast) var(--ease-out); }
  .footer-links a:hover { color: var(--text-primary); }
  .footer-copy { font-size: var(--t-xs); color: var(--text-quaternary); }

  @media (max-width: 860px) {
    .steps { grid-template-columns: repeat(2, 1fr); }
    .hero { padding-top: var(--s-11); }
  }
  @media (max-width: 520px) {
    .steps { grid-template-columns: 1fr; }
  }

  @media (prefers-reduced-motion: reduce) {
    .aurora span, .eyebrow .pip, .btn-primary { animation: none !important; }
  }
</style>
