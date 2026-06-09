<script>
  import { onMount } from 'svelte';
  import AuroraMockup from '$lib/components/AuroraMockup.svelte';

  // Seconds to hold on the last frame before the clip replays.
  const LOOP_PAUSE_MS = 10000;

  let muted = $state(true);
  let video = $state(null);
  let loopTimer;

  let theme = $state('dark'); // Default to dark for SSR/initial load

  onMount(() => {
    // Read theme from document.documentElement set by head script, or fallback
    const currentTheme = document.documentElement.getAttribute('data-theme') || 
      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    theme = currentTheme;
  });

  function toggleSound() {
    if (!video) return;
    muted = !muted;
    video.muted = muted;
    // Some browsers pause on first unmute gesture; make sure we keep playing.
    if (!muted) video.play?.();
  }

  function toggleTheme() {
    theme = theme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem('theme', theme);
    } catch (e) {}
  }

  // Replaced the native `loop` with a paced loop: when the clip ends, hold the
  // final frame for LOOP_PAUSE_MS, then rewind and play again.
  function onEnded() {
    clearTimeout(loopTimer);
    loopTimer = setTimeout(() => {
      if (!video) return;
      video.currentTime = 0;
      video.play?.();
    }, LOOP_PAUSE_MS);
  }
</script>

<svelte:head>
  <title>Vibes</title>
  <meta
    name="description"
    content="See which friends are online and coding — private ambient presence for small groups."
  />
</svelte:head>

<section class="hero" aria-label="Vibes">
  <div class="hero-inner">
    <!-- svelte-ignore a11y_media_has_caption -->
    <video
      bind:this={video}
      class="hero-video"
      poster="/hero/website-hero-poster.jpg"
      autoplay
      muted
      playsinline
      preload="auto"
      onended={onEnded}
    >
      <source src="/hero/website-hero.webm" type="video/webm" />
      <source src="/hero/website-hero.mp4" type="video/mp4" />
    </video>

    <button
      type="button"
      class="sound-toggle"
      onclick={toggleSound}
      aria-pressed={!muted}
      aria-label={muted ? "Turn sound on" : "Turn sound off"}
    >
      {#if muted}
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M4 9v6h3.5L13 19V5L7.5 9H4zM17 9.5l4 5M21 9.5l-4 5"
          />
        </svg>
      {:else}
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M4 9v6h3.5L13 19V5L7.5 9H4zM16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"
          />
        </svg>
      {/if}
    </button>

    <button
      type="button"
      class="theme-toggle"
      onclick={toggleTheme}
      aria-label={theme === 'dark' ? "Switch to light theme" : "Switch to dark theme"}
    >
      {#if theme === 'dark'}
        <!-- Moon icon -->
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"
          />
        </svg>
      {:else}
        <!-- Sun icon -->
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <circle cx="12" cy="12" r="5" fill="none" stroke="currentColor" stroke-width="1.8" />
          <path
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linecap="round"
            d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"
          />
        </svg>
      {/if}
    </button>
  </div>
</section>

<main>
  <section class="intro" aria-labelledby="home-title">
    <p class="eyebrow">vibes</p>
    <h1 id="home-title">See who's coding right now.</h1>
    <p class="subhead">Vibes shows which friends are online and how much they've coded today.</p>
    <p class="description">
      A Mac app for small groups. It turns your local Git activity into a simple, private friend feed.
    </p>
    <p class="privacy">
      Shares aggregate activity only. No repo paths, branches, commit messages, filenames, editor activity, process history, or transcripts.
    </p>
    <a class="download-link" href="/download">Download for Mac</a>
  </section>

  <figure class="product-visual">
    <AuroraMockup siteTheme={theme} />
    <figcaption>Interactive mockup of the Vibes Mac app. Try toggling light and dark mode on the window or website.</figcaption>
  </figure>

  <section class="steps" aria-labelledby="steps-title">
    <p class="section-label">get started</p>
    <h2 id="steps-title">Bring your group online.</h2>
    <ol>
      <li>
        <span>Download and install Vibes for macOS.</span>
      </li>
      <li>
        <span>Open it and enter a display name.</span>
      </li>
      <li>
        <span>Tap Add Friend to send a one-time invite link, or accept one you were sent.</span>
      </li>
      <li>
        <span>Add your local repos. You're online while you're coding, and one tap takes you offline.</span>
      </li>
    </ol>
  </section>
</main>

<style>
  /* --- Hero -------------------------------------------------------------- */
  /* The hero sits on the page background, not a separate black panel, so it
     reads as the top of one continuous surface. The magenta (left) and teal
     (right) glow is baked into this background; the video is feathered into
     it so there is no hard rectangle. A final vertical fade guarantees the
     bottom edge lands on exactly --bg, melting into the content below. */
  .hero {
    width: 100%;
    overflow: hidden;
    background:
      linear-gradient(to bottom, transparent 45%, var(--vibe-ink) 100%),
      radial-gradient(
        95% 78% at 14% 42%,
        rgba(155, 15, 82, 0.55),
        transparent 62%
      ),
      radial-gradient(
        95% 78% at 86% 42%,
        rgba(4, 86, 125, 0.6),
        transparent 62%
      ),
      var(--vibe-ink);
  }

  .hero-inner {
    position: relative;
    height: clamp(240px, 32vw, 440px);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  /* Sizing from height keeps the box at the clip's native 16:9, so the full
     frame is always shown (never cropped) and the mask aligns exactly to the
     video edges. In the desktop range the clip's width stays well under the
     viewport, so it never needs cropping or letterboxing. */
  .hero-video {
    height: 100%;
    width: auto;
    max-width: 100%;
    display: block;
    -webkit-mask-image:
      linear-gradient(
        to right,
        transparent 0,
        #000 11%,
        #000 89%,
        transparent 100%
      ),
      linear-gradient(to bottom, #000 0, #000 78%, transparent 100%);
    -webkit-mask-composite: source-in;
    mask-image:
      linear-gradient(
        to right,
        transparent 0,
        #000 11%,
        #000 89%,
        transparent 100%
      ),
      linear-gradient(to bottom, #000 0, #000 78%, transparent 100%);
    mask-composite: intersect;
  }

  .sound-toggle,
  .theme-toggle {
    position: absolute;
    right: var(--space-4);
    width: 2.25rem;
    height: 2.25rem;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    color: rgba(255, 255, 255, 0.92);
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 999px;
    cursor: pointer;
    backdrop-filter: blur(6px);
    transition:
      background 0.15s ease,
      border-color 0.15s ease,
      opacity 0.15s ease;
  }

  .sound-toggle {
    bottom: var(--space-4);
  }

  .theme-toggle {
    top: var(--space-4);
  }

  .sound-toggle:hover,
  .sound-toggle:focus-visible,
  .theme-toggle:hover,
  .theme-toggle:focus-visible {
    background: rgba(0, 0, 0, 0.55);
    border-color: rgba(255, 255, 255, 0.4);
  }

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
    .hero-inner {
      height: auto;
    }

    .hero-video {
      width: 100%;
      max-height: none;
    }

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
