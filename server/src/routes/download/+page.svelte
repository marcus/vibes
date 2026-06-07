<script>
  let { data } = $props();
</script>

<svelte:head>
  <title>Vibes for Mac</title>
  <meta
    name="description"
    content="Private ambient presence for small coding groups."
  />
</svelte:head>

<main class="download-page">
  <section class="download" aria-labelledby="download-title">
    <p class="eyebrow">vibes</p>
    <h1 id="download-title">Vibes for Mac</h1>
    <p class="summary">Private ambient presence for small coding groups.</p>

    <div class="actions" aria-label="Download options">
      <a class="primary-action" href="/downloads/Vibes.dmg">Download for macOS</a>
      <a class="checksum-link" href="/downloads/SHA256SUMS">SHA256 checksums</a>
    </div>

    <div class="release-meta" aria-label="Release details">
      <p>macOS 14 or newer. Signed and notarized.</p>
      {#if data.release?.version}
        <p>Current version {data.release.version}</p>
      {/if}
    </div>
  </section>
</main>

<style>
  .download-page {
    min-height: 100dvh;
    display: grid;
    place-items: center;
    padding: var(--space-12) var(--space-6);
  }

  .download {
    width: min(100%, 32rem);
    display: grid;
    gap: var(--space-6);
  }

  .eyebrow {
    margin: 0;
    color: var(--faint);
    font-size: var(--text-xs);
    font-weight: var(--weight-regular);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
  }

  h1 {
    margin: 0;
    font-size: var(--text-2xl);
    font-weight: var(--weight-light);
    line-height: var(--leading-tight);
  }

  .summary {
    max-width: 25rem;
    margin: calc(var(--space-4) * -1) 0 0;
    color: var(--muted);
    font-size: var(--text-lg);
    font-weight: var(--weight-light);
    line-height: 1.4;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-4);
    margin-top: var(--space-2);
  }

  .primary-action,
  .checksum-link {
    text-underline-offset: 0.18em;
  }

  .primary-action {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 2.75rem;
    padding: 0 var(--space-6);
    background: var(--fg);
    color: var(--bg);
    border-radius: var(--radius-sm);
    font-size: var(--text-sm);
    font-weight: var(--weight-medium);
    text-decoration: none;
  }

  .primary-action:hover,
  .primary-action:focus-visible {
    background: var(--accent);
    color: var(--vibe-paper);
  }

  .checksum-link {
    color: var(--muted);
    font-size: var(--text-sm);
  }

  .checksum-link:hover,
  .checksum-link:focus-visible {
    color: var(--fg);
  }

  .release-meta {
    display: grid;
    gap: var(--space-2);
    color: var(--muted);
    font-size: var(--text-sm);
  }

  .release-meta p {
    margin: 0;
  }

  @media (max-width: 520px) {
    .download-page {
      place-items: start stretch;
      padding: var(--space-12) var(--space-6);
    }

    .actions {
      align-items: stretch;
      flex-direction: column;
      gap: var(--space-3);
    }

    .primary-action {
      width: 100%;
    }
  }
</style>
