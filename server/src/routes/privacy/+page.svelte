<script>
  import MarketingShell from '$lib/components/MarketingShell.svelte';
  import SocialMeta from '$lib/components/SocialMeta.svelte';

  const description =
    "Vibes shares aggregate coding activity only. No repo paths, branches, commit messages, filenames, editor activity, process history, or transcripts.";
</script>

<svelte:head>
  <title>Privacy — Vibes</title>
  <meta name="description" content={description} />
</svelte:head>

<SocialMeta title="Privacy — Vibes" {description} path="/privacy" />

<MarketingShell>
  {#snippet children()}
    <section class="privacy-page shell">
      <div class="eyebrow"><span class="lockpip"></span> Privacy</div>
      <h1>Private <span class="spectrum-text">by design.</span></h1>
      <p class="lede">
        Vibes turns your local Git activity into a simple friend feed for a small group.
        It shares <b>aggregate activity only</b> — just enough to show who's coding and how much.
      </p>

      <div class="cols">
        <div class="card good">
          <h2>What friends see</h2>
          <ul>
            <li>Whether you're online right now</li>
            <li>Minutes coded today</li>
            <li>Lines added and removed, in total</li>
            <li>A commit count and your display name</li>
          </ul>
        </div>
        <div class="card bad">
          <h2>What never leaves your Mac</h2>
          <ul>
            <li>Repo paths and names</li>
            <li>Branches and commit messages</li>
            <li>Filenames and file contents</li>
            <li>Editor activity and process history</li>
            <li>AI transcripts or prompts</li>
          </ul>
        </div>
      </div>

      <div class="notes">
        <p><b>Your group only.</b> Activity is shared with the friends you've added by one-time invite — nobody else. You're online only while you're actively coding, and one tap takes you offline.</p>
        <p><b>No tracking, no accounts.</b> Vibes isn't an ad product. There's no analytics SDK, no third-party trackers, and no sign-up — it's a direct download for Apple Silicon.</p>
      </div>

      <div class="foot-cta">
        <a class="btn btn-primary" href="/download">
          <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
          Download for Mac
        </a>
      </div>
    </section>
  {/snippet}
</MarketingShell>

<style>
  .privacy-page {
    max-width: 820px;
    margin: 0 auto;
    padding: var(--s-12) var(--s-6) var(--s-12);
  }

  .eyebrow {
    display: inline-flex; align-items: center; gap: var(--s-2);
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--text-tertiary); margin-bottom: var(--s-5);
  }
  .eyebrow .lockpip { width: 7px; height: 7px; border-radius: 50%; background: var(--v-cyan); box-shadow: 0 0 10px var(--v-cyan); }

  .privacy-page h1 {
    font-size: clamp(36px, 5.5vw, var(--t-5xl));
    font-weight: 800; letter-spacing: -0.04em; line-height: 1.0;
  }
  .lede {
    max-width: 620px; margin: var(--s-5) 0 0;
    font-size: clamp(16px, 2vw, var(--t-lg));
    color: var(--text-secondary); line-height: 1.5;
  }
  .lede b { color: var(--text-primary); font-weight: 600; }

  .cols {
    display: grid; grid-template-columns: 1fr 1fr; gap: var(--s-4);
    margin-top: var(--s-9);
  }
  .card {
    padding: var(--s-6);
    background: var(--bg-secondary); border: 1px solid var(--border-subtle);
    border-radius: var(--r-lg);
  }
  .card h2 {
    font-size: var(--t-base); font-weight: 700; letter-spacing: -0.01em;
    margin-bottom: var(--s-4); color: var(--text-primary);
  }
  .card ul { margin: 0; padding: 0; list-style: none; display: grid; gap: var(--s-3); }
  .card li {
    position: relative; padding-left: var(--s-6);
    font-size: var(--t-md); color: var(--text-secondary); line-height: 1.35;
  }
  .card li::before {
    position: absolute; left: 0; top: 0;
    font-weight: 700;
  }
  .card.good li::before { content: "✓"; color: var(--status-online); }
  .card.bad li::before { content: "✕"; color: var(--v-pink); }

  .notes {
    display: grid; gap: var(--s-4);
    margin-top: var(--s-8);
    max-width: 720px;
  }
  .notes p { font-size: var(--t-base); color: var(--text-secondary); line-height: 1.55; }
  .notes b { color: var(--text-primary); font-weight: 600; }

  .foot-cta { margin-top: var(--s-10); }

  @media (max-width: 640px) {
    .cols { grid-template-columns: 1fr; }
  }
</style>
