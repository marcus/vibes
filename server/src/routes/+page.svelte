<script>
  import OrbitMockup from '$lib/components/OrbitMockup.svelte';
  import MarketingShell from '$lib/components/MarketingShell.svelte';
  import SocialMeta from '$lib/components/SocialMeta.svelte';
  import HeroRibbons from '$lib/components/HeroRibbons.svelte';

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
      <HeroRibbons />

      <div class="eyebrow"><span class="pip"></span> Right now · 3 friends in orbit</div>
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
