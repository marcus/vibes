<script>
  import { tick } from 'svelte';
  import MarketingShell from '$lib/components/MarketingShell.svelte';
  import SocialMeta from '$lib/components/SocialMeta.svelte';
  import HeroRibbons from '$lib/components/HeroRibbons.svelte';
  import OrbitMockup from '$lib/components/OrbitMockup.svelte';

  let { data } = $props();

  let copied = $state(false);
  let downloadCopyFailed = $state(false);
  let copyAlert;
  let copyTimer;
  const appURL = $derived(`vibes://invite/${encodeURIComponent(data.code ?? "")}`);

  const metaTitle = $derived(
    data.state !== "open"
      ? "Vibes invite"
      : data.inviter
        ? `${data.inviter} invited you to Vibes`
        : "You're invited to Vibes"
  );
  const description =
    "Vibes shows which friends are online and coding — private ambient presence for small groups of coders on macOS.";

  $effect(() => () => clearTimeout(copyTimer));

  async function copyCode() {
    if (!data.code) return;
    try {
      await navigator.clipboard.writeText(data.code);
      copied = true;
      downloadCopyFailed = false;
      clearTimeout(copyTimer);
      copyTimer = setTimeout(() => (copied = false), 2000);
    } catch {
      // Clipboard may be unavailable (blocked or insecure context). The code is
      // selectable, so the user can still copy it manually.
    }
  }

  // Deferred deep link: stash the invite link on the clipboard as the visitor
  // heads to the download, so the app's first-run setup can detect it and
  // accept the invite without them returning to this page. Copy first, then
  // navigate — a pending clipboard write can be dropped on unload.
  async function downloadWithInvite(event) {
    if (!data.code) return;
    event.preventDefault();
    try {
      await navigator.clipboard.writeText(new URL(`/i/${encodeURIComponent(data.code)}`, window.location.origin).href);
      downloadCopyFailed = false;
    } catch {
      downloadCopyFailed = true;
      await tick();
      copyAlert?.focus();
      return;
    }
    window.location.assign(event.currentTarget?.href ?? "/download");
  }
</script>

<svelte:head>
  <title>{metaTitle}</title>
  <meta name="description" content={description} />
  <meta name="robots" content="noindex" />
</svelte:head>

<SocialMeta title={metaTitle} {description} path={`/invite/${encodeURIComponent(data.code ?? "")}`} />

<MarketingShell>
  {#snippet children(theme)}
    <section class="hero shell">
      <HeroRibbons />

      {#if data.state !== "open"}
        <div class="eyebrow">Invite link</div>
        <h1>This invite can't<br />be used.</h1>
        <p class="hero-sub">It may have expired, already been used, or been revoked.</p>
        <p class="hero-lede">
          Ask your friend for a fresh link — or grab the app so you're ready when it arrives.
        </p>
        <div class="hero-cta">
          <a class="btn btn-primary" href="/download">
            <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
            Download for Mac
          </a>
        </div>
      {:else}
        <div class="eyebrow">
          <span class="pip"></span>
          {#if data.inviter}{data.inviter} invited you to Vibes{:else}You're invited to Vibes{/if}
        </div>
        <h1>Join your friends<br /><span class="spectrum-text">in orbit.</span></h1>
        <p class="hero-sub">Vibes shows which friends are online and how much they've coded today.</p>
        <p class="hero-lede">A Mac app for small groups. It turns your local Git activity into a simple, private friend feed.</p>

        <div class="hero-cta split-cta">
          <div class="cta-path">
            <span class="cta-label">New here?</span>
            <a class="btn btn-primary" href="/download" onclick={downloadWithInvite}>
              <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
              Download and copy invite
            </a>
          </div>
          <div class="cta-path">
            <span class="cta-label">Already installed?</span>
            <a class="btn btn-ghost" href={appURL}>Open in Vibes</a>
          </div>
        </div>
        <p class="hero-fine">
          After installing, open Vibes. If you see "You have a Vibes invite," just enter your display name.
          If not, paste the invite code below.
        </p>
        {#if downloadCopyFailed}
          <p class="copy-alert" role="alert" aria-live="assertive" tabindex="-1" bind:this={copyAlert}>
            Your browser did not let us copy the invite. Copy the code below, then
            <a href="/download">continue to download</a>.
          </p>
        {/if}

        <div class="code-card">
          <span class="code-label">Need it later?</span>
          <div class="code-row">
            <code>{data.code}</code>
            <button type="button" class="copy" onclick={copyCode}>{copied ? "copied" : "copy"}</button>
          </div>
          <p class="code-hint">If the app does not find your invite automatically, paste this code in Vibes -> Invite -> Have an invite code.</p>
        </div>

        <div class="privacy">
          <svg class="lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          <span><b>Shares aggregate activity only.</b> No repo paths, branches, commit messages, filenames, editor activity, process history, or transcripts.</span>
        </div>
      {/if}
    </section>

    {#if data.state === "open"}
      <!-- Same interactive mockup as the homepage, so invitees see what they're installing. -->
      <section class="stage shell">
        <div class="window-wrap">
          <OrbitMockup siteTheme={theme} />
        </div>
        <p class="stage-cap">Interactive mockup of the Vibes Mac app. <b>Try the orbit / list toggle.</b></p>
      </section>

      <section class="getstarted shell">
        <div class="section-head">
          <div class="section-eyebrow">Get started</div>
          <h2>Three steps to join.</h2>
        </div>
        <div class="steps">
          <div class="step">
            <div class="step-num">01</div>
            <h3>Install</h3>
            <p>Download and install Vibes for macOS, then open it.</p>
          </div>
          <div class="step">
            <div class="step-num">02</div>
            <h3>Accept the invite</h3>
            <p>Enter a display name. Vibes accepts the copied invite during setup.</p>
          </div>
          <div class="step">
            <div class="step-num">03</div>
            <h3>Add your repos</h3>
            <p>You're online while you're coding, and one tap takes you offline.</p>
          </div>
        </div>
      </section>
    {/if}
  {/snippet}
</MarketingShell>

<style>
  .hero { padding: var(--s-12) 0 var(--s-9); text-align: center; }

  .eyebrow {
    display: inline-flex; align-items: center; gap: var(--s-2);
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--text-tertiary); margin-bottom: var(--s-6);
  }
  .eyebrow .pip { width: 7px; height: 7px; border-radius: 50%; background: var(--status-online);
    box-shadow: 0 0 10px var(--status-online); animation: breathe 2.6s var(--ease-in-out) infinite; }
  @keyframes breathe { 0%,100%{ opacity:1; transform: scale(1);} 50%{ opacity:.55; transform: scale(.8);} }

  h1 {
    font-size: clamp(40px, 6.6vw, var(--t-6xl));
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
  .split-cta { align-items: end; gap: var(--s-5); }
  .cta-path { display: grid; gap: var(--s-2); justify-items: center; }
  .cta-label {
    font-size: var(--t-xs);
    font-weight: 600;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--text-tertiary);
  }
  .hero-fine { margin-top: var(--s-3); font-size: var(--t-xs); color: var(--text-tertiary); }
  .copy-alert {
    max-width: 460px;
    margin: var(--s-4) auto 0;
    padding: var(--s-3) var(--s-4);
    border: 1px solid color-mix(in oklab, var(--accent-default) 35%, var(--border-subtle));
    border-radius: var(--r-md);
    background: color-mix(in oklab, var(--accent-default) 8%, var(--bg-secondary));
    color: var(--text-secondary);
    font-size: var(--t-sm);
    line-height: 1.35;
  }
  .copy-alert a { color: var(--accent-default); font-weight: 600; }
  .copy-alert a:hover { text-decoration: underline; }

  /* ---- Invite code ---- */
  .code-card {
    max-width: 480px; margin: var(--s-9) auto 0;
    padding: var(--s-5) var(--s-6);
    text-align: left;
    background: var(--bg-secondary); border: 1px solid var(--border-subtle);
    border-radius: var(--r-lg);
  }
  .code-label {
    display: block;
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--text-tertiary); margin-bottom: var(--s-3);
  }
  .code-row { display: flex; gap: var(--s-2); align-items: stretch; }
  code {
    flex: 1;
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: var(--t-md);
    background: var(--bg-base);
    border: 1px solid var(--border-subtle);
    border-radius: var(--r-md);
    padding: var(--s-3) var(--s-4);
    user-select: all;
    word-break: break-all;
  }
  .copy {
    font: inherit; font-size: var(--t-sm); font-weight: 600;
    color: var(--text-primary);
    background: var(--bg-base);
    border: 1px solid var(--border-subtle);
    border-radius: var(--r-md);
    padding: 0 var(--s-5);
    cursor: pointer;
    transition: border-color var(--dur-normal) var(--ease-out), transform var(--dur-normal) var(--ease-out);
  }
  .copy:hover { border-color: var(--border-strong); transform: translateY(-1px); }
  .copy:active { transform: translateY(0); }
  .code-hint { margin-top: var(--s-3); font-size: var(--t-sm); color: var(--text-tertiary); }

  /* Privacy line (matches homepage) */
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

  /* ---- Mockup stage (matches homepage) ---- */
  .stage { padding: var(--s-9) 0 var(--s-12); }
  .window-wrap { perspective: 2000px; }
  .stage-cap { text-align: center; margin-top: var(--s-6); font-size: var(--t-sm); color: var(--text-tertiary); }
  .stage-cap b { color: var(--text-secondary); font-weight: 500; }

  /* ---- Get started (matches homepage, 3-up) ---- */
  .getstarted { padding: var(--s-10) 0 var(--s-13); }
  .section-head { text-align: center; margin-bottom: var(--s-10); }
  .section-eyebrow {
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--accent-default); margin-bottom: var(--s-3);
  }
  .section-head h2 { font-size: clamp(30px, 4.4vw, var(--t-5xl)); font-weight: 800; letter-spacing: -0.022em; }

  .steps { display: grid; grid-template-columns: repeat(3, 1fr); gap: var(--s-4); }
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

  @media (max-width: 860px) {
    .steps { grid-template-columns: 1fr; }
    .hero { padding-top: var(--s-11); }
  }

  @media (max-width: 640px) {
    .split-cta { align-items: stretch; }
    .cta-path { justify-items: stretch; width: 100%; }
    .cta-path :global(.btn) { justify-content: center; width: 100%; }
  }

  @media (prefers-reduced-motion: reduce) {
    .eyebrow .pip { animation: none !important; }
  }
</style>
