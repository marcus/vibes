<svelte:head>
  <title>Vibes</title>
  <meta
    name="description"
    content="Private ambient presence for small coding groups."
  />
</svelte:head>

<main>
  <section class="intro" aria-labelledby="home-title">
    <p class="eyebrow">vibes</p>
    <h1 id="home-title">A quiet presence layer for coding friends.</h1>
    <p class="subhead">See who is around, what kind of day they are having, and when they prefer quiet.</p>
    <p class="description">
      Vibes is a Mac app for small groups. It turns local Git activity and an optional status into a simple friend feed.
    </p>
    <p class="privacy">
      Shares aggregate activity only. No repo paths, branches, commit messages, filenames, editor activity, process history, or transcripts.
    </p>
    <a class="download-link" href="/download">Download for Mac</a>
  </section>

  <figure class="product-visual">
    <img
      src="/images/vibes-aspirational-screenshot.png"
      alt="Stylized mockup of the Vibes Mac app showing a quiet friend presence feed."
      width="1536"
      height="1024"
    />
    <figcaption>Concept mockup, not a screenshot of the current app.</figcaption>
  </figure>

  <section class="steps" aria-labelledby="steps-title">
    <p class="section-label">get started</p>
    <h2 id="steps-title">Bring your group online.</h2>
    <ol>
      <li>
        <span>Download and install Vibes for macOS.</span>
      </li>
      <li>
        <span>Get a relay token from the person running your group.</span>
      </li>
      <li>
        <span>Add the local Git repos you want summarized.</span>
      </li>
      <li>
        <span>Choose Broadcasting, Quiet, or Offline.</span>
      </li>
    </ol>
  </section>
</main>

<style>
  main {
    width: min(100%, 72rem);
    margin: 0 auto;
    padding: clamp(var(--space-12), 9vw, 7rem) var(--space-8) var(--space-16);
  }

  .intro {
    width: min(100%, 42rem);
    display: grid;
    gap: var(--space-4);
  }

  .eyebrow,
  .section-label {
    margin: 0;
    color: var(--faint);
    font-size: var(--text-xs);
    font-weight: var(--weight-regular);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
  }

  h1,
  h2,
  p {
    margin: 0;
  }

  h1 {
    max-width: 13ch;
    font-size: clamp(3rem, 7.5vw, 5.75rem);
    font-weight: var(--weight-light);
    line-height: 0.97;
  }

  .subhead {
    max-width: 34rem;
    color: var(--muted);
    font-size: var(--text-xl);
    font-weight: var(--weight-light);
    line-height: 1.24;
  }

  .description {
    max-width: 32rem;
    color: var(--fg);
    font-size: var(--text-base);
  }

  .privacy {
    max-width: 34rem;
    color: var(--faint);
    font-size: var(--text-xs);
    line-height: 1.45;
  }

  .download-link {
    width: fit-content;
    min-height: 2.75rem;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    margin-top: var(--space-2);
    padding: 0 var(--space-6);
    background: var(--fg);
    color: var(--bg);
    border-radius: var(--radius-sm);
    font-size: var(--text-sm);
    font-weight: var(--weight-medium);
    text-decoration: none;
  }

  .download-link:hover,
  .download-link:focus-visible {
    background: var(--accent);
    color: var(--vibe-paper);
  }

  .product-visual {
    margin: clamp(var(--space-12), 8vw, 5.5rem) 0 0;
  }

  .product-visual img {
    width: min(100%, 58rem);
    height: auto;
    display: block;
  }

  .product-visual figcaption {
    margin-top: var(--space-3);
    color: var(--faint);
    font-size: var(--text-xs);
  }

  .steps {
    width: min(100%, 42rem);
    display: grid;
    gap: var(--space-6);
    margin-top: clamp(var(--space-12), 9vw, 6rem);
  }

  h2 {
    max-width: 16rem;
    font-size: var(--text-2xl);
    font-weight: var(--weight-light);
    line-height: var(--leading-tight);
  }

  ol {
    margin: 0;
    padding: 0;
    list-style: none;
    counter-reset: steps;
  }

  li {
    counter-increment: steps;
    display: grid;
    grid-template-columns: 2.5rem minmax(0, 1fr);
    gap: var(--space-6);
    padding: 1.25rem 0;
    color: var(--muted);
    border-top: 1px solid var(--hairline);
  }

  li:last-child {
    border-bottom: 1px solid var(--hairline);
  }

  li::before {
    content: counter(steps, decimal-leading-zero);
    color: var(--faint);
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
  }

  li span {
    color: var(--fg);
  }

  @media (max-width: 720px) {
    main {
      padding: var(--space-12) var(--space-6) var(--space-16);
    }

    h1 {
      max-width: 9ch;
      font-size: clamp(3rem, 17vw, 5rem);
    }

    .subhead {
      font-size: var(--text-lg);
    }

    .product-visual {
      margin-left: calc(var(--space-6) * -1);
      margin-right: calc(var(--space-6) * -1);
    }

    .product-visual figcaption {
      padding: 0 var(--space-6);
    }
  }
</style>
