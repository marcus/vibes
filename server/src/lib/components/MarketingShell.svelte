<script>
  import { onMount } from 'svelte';
  import '$lib/styles/marketing.css';

  let { children } = $props();

  let theme = $state('dark'); // Dark is the default

  onMount(() => {
    let saved;
    try {
      saved = localStorage.getItem('theme');
    } catch (e) {}
    // Dark is the default; only an explicit saved 'light' choice opts out.
    const resolved = saved === 'light' ? 'light' : 'dark';
    theme = resolved;
    document.documentElement.setAttribute('data-theme', resolved);
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
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
  <link
    href="https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600;700;800&display=swap"
    rel="stylesheet"
  />
</svelte:head>

<div class="mkt">
  <!-- Animated aurora backdrop -->
  <div class="aurora" aria-hidden="true">
    <span class="a1"></span><span class="a2"></span><span class="a3"></span><span class="a4"></span>
  </div>
  <div class="grain" aria-hidden="true"></div>

  <!-- ===================== NAV ===================== -->
  <nav class="nav">
    <a class="brand" href="/" aria-label="Vibes home">
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

  <main class="mkt-main">
    {@render children(theme)}
  </main>

  <!-- ===================== FOOTER ===================== -->
  <footer class="footer">
    <div class="shell footer-in">
      <a class="brand" href="/">
        <img class="mark" src="/images/vibes-icon.png" srcset="/images/vibes-icon.png 1x, /images/vibes-icon@2x.png 2x" width="24" height="24" alt="" />
        <span class="word">Vibes</span>
      </a>
      <div class="nav-spacer"></div>
      <div class="footer-links">
        <a href="/download">Download</a>
        <a href="/privacy">Privacy</a>
        <a href="/">Made for friends</a>
      </div>
      <span class="footer-copy">© Vibes 2026</span>
    </div>
  </footer>
</div>
