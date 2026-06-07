<main>
  <section class="hero" aria-labelledby="home-title">
    <div class="wordmark" id="home-title">vibes</div>
    <p class="tagline">a quiet presence layer for coding friends</p>
  </section>

  <section class="trust" aria-labelledby="trust-title">
    <p class="section-label" id="trust-title">what it is</p>
    <div class="trust-grid">
      <p class="summary">
        Vibes is a free, open-source Mac app for small groups who want a low-key
        sense of who is around and building today.
      </p>
      <div class="details">
        <p>
          The app scans local Git repos, aggregates the day into broad activity
          stats, and only publishes what you choose to share with friends:
          presence mode, optional status text, derived vibe, aggregate Git stats,
          and optional cards such as repo aliases or agent mix.
        </p>
        <p>
          It does not publish raw repo paths, branch names, commit messages,
          filenames, editor activity, process history, or agent transcripts. The
          relay stores the latest friend-visible status for your feed. There is
          no telemetry product, no ads, and no data sale.
        </p>
      </div>
    </div>
  </section>
</main>

<style>
  main {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: clamp(var(--space-12), 12vh, 7rem);
    padding: var(--space-16) var(--space-8);
  }

  .hero {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-4);
    text-align: center;
  }

  .wordmark {
    font-size: var(--text-2xl);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
  }

  .tagline {
    margin: 0;
    color: var(--muted);
    font-weight: var(--weight-light);
  }

  .trust {
    width: min(100%, 46rem);
  }

  .section-label {
    margin: 0 0 var(--space-6);
    color: var(--faint);
    font-size: var(--text-xs);
    font-weight: var(--weight-regular);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
  }

  .trust-grid {
    display: grid;
    grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.35fr);
    gap: var(--space-12);
    align-items: start;
  }

  .summary {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: var(--weight-light);
    line-height: 1.35;
  }

  .details {
    display: grid;
    gap: var(--space-4);
    color: var(--muted);
    font-size: var(--text-sm);
  }

  .details p {
    margin: 0;
  }

  @media (max-width: 720px) {
    main {
      align-items: stretch;
      gap: var(--space-12);
      padding: var(--space-12) var(--space-6);
    }

    .hero {
      align-items: flex-start;
      text-align: left;
    }

    .trust-grid {
      grid-template-columns: 1fr;
      gap: var(--space-6);
    }
  }
</style>
