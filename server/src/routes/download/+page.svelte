<script>
  import MarketingShell from '$lib/components/MarketingShell.svelte';

  let { data } = $props();
</script>

<svelte:head>
  <title>Download Vibes for Mac</title>
  <meta
    name="description"
    content="Download Vibes for macOS — private ambient presence for small coding groups. For Apple Silicon."
  />
</svelte:head>

<MarketingShell>
  {#snippet children()}
    <section class="download shell">
      <div class="eyebrow"><span class="pip"></span> For Apple Silicon · macOS 26</div>
      <h1>Vibes <span class="spectrum-text">for Mac.</span></h1>
      <p class="summary">Private ambient presence for small coding groups. Direct download — no App Store, no account.</p>

      <div class="actions">
        <a class="btn btn-primary" href="/downloads/Vibes.dmg">
          <svg class="apple" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
          Download for macOS
        </a>
        <a class="btn btn-ghost" href="/downloads/SHA256SUMS">SHA256 checksums</a>
      </div>

      <div class="release-meta">
        <p>macOS 14 or newer. Signed and notarized.</p>
        {#if data.release?.version}
          <p>Current version <b>{data.release.version}</b></p>
        {/if}
      </div>

      <div class="privacy">
        <svg class="lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
        <span><b>Shares aggregate activity only.</b> No repo paths, branches, commit messages, filenames, editor activity, process history, or transcripts. <a href="/privacy">Read the privacy summary →</a></span>
      </div>
    </section>
  {/snippet}
</MarketingShell>

<style>
  .download {
    max-width: 640px;
    padding: var(--s-13) var(--s-6) var(--s-12);
    text-align: center;
    margin: 0 auto;
  }

  .eyebrow {
    display: inline-flex; align-items: center; gap: var(--s-2);
    font-size: var(--t-xs); font-weight: 600;
    letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--text-tertiary); margin-bottom: var(--s-6);
  }
  .eyebrow .pip { width: 7px; height: 7px; border-radius: 50%; background: var(--status-online);
    box-shadow: 0 0 10px var(--status-online); }

  .download h1 {
    font-size: clamp(40px, 6vw, var(--t-6xl));
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 1.0;
  }
  .summary {
    max-width: 460px; margin: var(--s-5) auto 0;
    font-size: clamp(16px, 2vw, var(--t-lg));
    color: var(--text-secondary); line-height: 1.4;
  }

  .actions {
    display: flex; gap: var(--s-3);
    justify-content: center; align-items: center;
    margin-top: var(--s-8); flex-wrap: wrap;
  }

  .release-meta {
    display: grid; gap: var(--s-1);
    margin-top: var(--s-5);
    color: var(--text-tertiary); font-size: var(--t-sm);
  }
  .release-meta b { color: var(--text-secondary); font-weight: 600; }

  .privacy {
    display: inline-flex; align-items: center; gap: var(--s-3);
    max-width: 600px; margin: var(--s-10) auto 0;
    padding: var(--s-3) var(--s-5);
    font-size: var(--t-md); color: var(--text-secondary);
    line-height: 1.4; text-align: left;
    background: var(--bg-secondary); border: 1px solid var(--border-subtle);
    border-radius: var(--r-lg);
  }
  .privacy .lock { flex-shrink: 0; width: 16px; height: 16px; color: var(--v-cyan); }
  .privacy b { color: var(--text-primary); font-weight: 600; }
  .privacy a { color: var(--v-cyan); font-weight: 500; white-space: nowrap; }
  .privacy a:hover { text-decoration: underline; }

  @media (max-width: 520px) {
    .actions { flex-direction: column; align-items: stretch; }
    .actions :global(.btn) { width: 100%; justify-content: center; }
  }
</style>
