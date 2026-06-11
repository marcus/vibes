<script>
  import OrbitMockup from '$lib/components/OrbitMockup.svelte';
  import MarketingShell from '$lib/components/MarketingShell.svelte';
  import SocialMeta from '$lib/components/SocialMeta.svelte';

  const description =
    "See which friends are online and coding — private ambient presence for small groups of coders on macOS.";
</script>

<svelte:head>
  <title>Vibes — See who's coding right now</title>
  <meta name="description" content={description} />
</svelte:head>

<SocialMeta title="Vibes — See who's coding right now" {description} path="/" />

<MarketingShell>
  {#snippet children(theme)}
    <!-- ===================== HERO ===================== -->
    <section class="hero shell">
      <!-- Option C2 · neon ribbons + fine density strands -->
      <div class="hero-ribbons" aria-hidden="true">
        <svg viewBox="0 0 1040 420" preserveAspectRatio="xMidYMid slice">
          <defs>
            <linearGradient id="ribA" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stop-color="#a472ff" /><stop offset="50%" stop-color="#ff4d8d" /><stop offset="100%" stop-color="#ff7a3d" />
            </linearGradient>
            <linearGradient id="ribB" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stop-color="#ff7a3d" /><stop offset="55%" stop-color="#ff4d8d" /><stop offset="100%" stop-color="#45d4ff" />
            </linearGradient>
            <linearGradient id="ribC" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stop-color="#6f8cff" /><stop offset="50%" stop-color="#45d4ff" /><stop offset="100%" stop-color="#a472ff" />
            </linearGradient>
          </defs>
          <g class="rib-blur" fill="none" stroke-linecap="round">
            <path d="M-40 150 C 220 40, 360 280, 620 150 S 980 90, 1120 200" stroke="url(#ribA)" stroke-width="10" />
            <path d="M-40 260 C 240 360, 420 120, 640 250 S 1000 320, 1120 210" stroke="url(#ribB)" stroke-width="14" />
            <path d="M-40 90 C 300 180, 520 -20, 760 110 S 1040 40, 1120 120" stroke="url(#ribC)" stroke-width="8" />
          </g>
          <g class="rib-thin-soft" fill="none" stroke-linecap="round" stroke-width="1.5">
            <path d="M-40 130 C 240 80, 440 210, 680 130 S 1010 70, 1120 150" stroke="url(#ribA)" />
            <path d="M-40 290 C 200 240, 420 350, 660 285 S 990 350, 1120 295" stroke="url(#ribB)" />
          </g>
          <g class="rib-thin" fill="none" stroke-linecap="round" stroke-width="1">
            <path d="M-40 110 C 220 60, 420 190, 660 110 S 1000 55, 1120 130" stroke="url(#ribA)" />
            <path d="M-40 175 C 240 140, 460 245, 700 180 S 1010 135, 1120 195" stroke="url(#ribC)" />
            <path d="M-40 235 C 180 285, 400 170, 640 235 S 980 285, 1120 225" stroke="url(#ribB)" />
            <path d="M-40 300 C 220 255, 440 360, 680 300 S 1000 355, 1120 295" stroke="url(#ribC)" />
            <path d="M-40 70 C 260 120, 500 30, 740 95 S 1030 40, 1120 80" stroke="url(#ribA)" />
            <path d="M-40 340 C 200 305, 420 395, 680 340 S 1000 385, 1120 335" stroke="url(#ribB)" />
            <path d="M-40 205 C 300 165, 520 265, 760 205 S 1040 160, 1120 215" stroke="url(#ribC)" />
          </g>
          <g class="rib-sharp" fill="none" stroke-linecap="round">
            <path d="M-40 150 C 220 40, 360 280, 620 150 S 980 90, 1120 200" stroke="url(#ribA)" stroke-width="2" />
            <path d="M-40 260 C 240 360, 420 120, 640 250 S 1000 320, 1120 210" stroke="url(#ribB)" stroke-width="2.5" />
          </g>
        </svg>
      </div>

      <div class="eyebrow"><span class="pip"></span> Right now · 4 friends in orbit</div>
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
        <OrbitMockup siteTheme={theme} />
      </div>
      <p class="stage-cap">Interactive mockup of the Vibes Mac app. <b>Try the orbit / list toggle</b> — and light or dark mode on the window or website.</p>
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
  {/snippet}
</MarketingShell>

<style>
  /* ---- Hero ---- */
  .hero { padding: var(--s-13) 0 var(--s-10); text-align: center; }

  /* Option C2 · neon ribbons backdrop behind the headline */
  .hero-ribbons {
    position: absolute; inset: -8% -12% auto -12%; height: 132%;
    z-index: -1; pointer-events: none;
  }
  .hero-ribbons svg { position: absolute; inset: 0; width: 100%; height: 100%; }
  /* readability scrim — a stronger feathered core right behind the copy,
     plus an outer fade that blends ribbons into the page base (both themes) */
  .hero-ribbons::after {
    content: ""; position: absolute; inset: 0;
    background:
      radial-gradient(ellipse 56% 50% at 50% 40%,
        color-mix(in srgb, var(--bg-base) 80%, transparent) 0%,
        color-mix(in srgb, var(--bg-base) 55%, transparent) 34%,
        transparent 70%),
      radial-gradient(ellipse 62% 60% at 50% 40%, transparent 18%, var(--bg-base) 82%);
  }
  .hero-ribbons .rib-blur { filter: blur(14px) saturate(1.3); opacity: 0.85; }
  .hero-ribbons .rib-sharp { opacity: 0.9; }
  .hero-ribbons .rib-thin { opacity: 0.55; }
  .hero-ribbons .rib-thin-soft { filter: blur(2px); opacity: 0.4; }
  /* neon reads softer on a light canvas */
  :global(html[data-theme="light"]) .hero-ribbons { opacity: 0.62; }
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

  @media (max-width: 860px) {
    .steps { grid-template-columns: repeat(2, 1fr); }
    .hero { padding-top: var(--s-11); }
  }
  @media (max-width: 520px) {
    .steps { grid-template-columns: 1fr; }
  }

  @media (prefers-reduced-motion: reduce) {
    .eyebrow .pip { animation: none !important; }
  }
</style>
