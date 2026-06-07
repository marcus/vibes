<script>
  import { page } from "$app/stores";
  import { goto } from "$app/navigation";
  import Icon from "./Icon.svelte";
  import Modal from "./Modal.svelte";
  import Toaster from "./Toaster.svelte";

  /** App chrome for every authenticated admin page: nav rail, keyboard nav,
   *  shortcut help, and the toast outlet. */
  let { session, children } = $props();

  const NAV = [
    { href: "/admin", label: "Overview", icon: "overview", match: (p) => p === "/admin" },
    { href: "/admin/users", label: "Users", icon: "users", match: (p) => p.startsWith("/admin/users") },
    { href: "/admin/invites", label: "Invites", icon: "invites", match: (p) => p.startsWith("/admin/invites") },
  ];

  let pathname = $derived($page.url.pathname);
  let navOpen = $state(false); // mobile drawer
  let helpOpen = $state(false);
  let awaitingG = $state(false);
  let gTimer = null;

  function isTyping(target) {
    if (!target) return false;
    const tag = target.tagName;
    return (
      tag === "INPUT" ||
      tag === "TEXTAREA" ||
      tag === "SELECT" ||
      target.isContentEditable
    );
  }

  function focusSearch() {
    const el = document.querySelector("[data-search] input");
    if (el) {
      el.focus();
      return true;
    }
    return false;
  }

  function onKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (isTyping(event.target)) {
      if (event.key === "Escape") event.target.blur();
      return;
    }

    if (awaitingG) {
      const dest = { o: "/admin", u: "/admin/users", i: "/admin/invites" }[event.key];
      awaitingG = false;
      clearTimeout(gTimer);
      if (dest) {
        event.preventDefault();
        goto(dest);
      }
      return;
    }

    if (event.key === "/") {
      if (focusSearch()) event.preventDefault();
      return;
    }
    if (event.key === "?") {
      event.preventDefault();
      helpOpen = !helpOpen;
      return;
    }
    if (event.key === "g") {
      awaitingG = true;
      clearTimeout(gTimer);
      gTimer = setTimeout(() => (awaitingG = false), 1200);
    }
  }
</script>

<svelte:window onkeydown={onKeydown} />

<div class="shell">
  <aside class="rail" class:open={navOpen}>
    <div class="brand">
      <a class="wordmark" href="/admin">vibes</a>
      <span class="tag">admin</span>
    </div>

    <nav class="nav">
      {#each NAV as item (item.href)}
        <a
          class="nav-link"
          class:active={item.match(pathname)}
          href={item.href}
          aria-current={item.match(pathname) ? "page" : undefined}
          onclick={() => (navOpen = false)}
        >
          <Icon name={item.icon} size={17} />
          <span>{item.label}</span>
        </a>
      {/each}
    </nav>

    <div class="rail-foot">
      <button type="button" class="help-btn" onclick={() => (helpOpen = true)}>
        <span class="session">
          <Icon name="shield" size={14} />
          {session?.kind ?? "admin"} session
        </span>
        <kbd>?</kbd>
      </button>
      <form method="POST" action="/admin/logout" class="logout">
        <button type="submit" class="logout-btn">
          <Icon name="logout" size={15} />
          <span>Sign out</span>
        </button>
      </form>
    </div>
  </aside>

  {#if navOpen}
    <button class="scrim" aria-label="Close navigation" onclick={() => (navOpen = false)}></button>
  {/if}

  <div class="main-wrap">
    <header class="topbar">
      <button class="menu" onclick={() => (navOpen = !navOpen)} aria-label="Toggle navigation">
        <Icon name="overview" size={18} />
      </button>
      <a class="topbar-brand" href="/admin">vibes <span>admin</span></a>
    </header>

    <main class="main">
      <div class="content">
        {@render children?.()}
      </div>
    </main>
  </div>
</div>

<Toaster />

<Modal bind:open={helpOpen} title="Keyboard shortcuts" size="sm">
  <dl class="shortcuts">
    <div><dt><kbd>/</kbd></dt><dd>Focus search</dd></div>
    <div><dt><kbd>g</kbd> <kbd>o</kbd></dt><dd>Go to overview</dd></div>
    <div><dt><kbd>g</kbd> <kbd>u</kbd></dt><dd>Go to users</dd></div>
    <div><dt><kbd>g</kbd> <kbd>i</kbd></dt><dd>Go to invites</dd></div>
    <div><dt><kbd>?</kbd></dt><dd>Toggle this help</dd></div>
    <div><dt><kbd>Esc</kbd></dt><dd>Close dialogs / clear search</dd></div>
  </dl>
</Modal>

<style>
  .shell {
    min-height: 100dvh;
    display: grid;
    grid-template-columns: 15rem 1fr;
  }

  .rail {
    position: sticky;
    top: 0;
    align-self: start;
    height: 100dvh;
    display: flex;
    flex-direction: column;
    padding: var(--space-6) var(--space-4);
    border-right: 1px solid var(--hairline);
  }

  .brand {
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
    padding: 0 var(--space-2);
    margin-bottom: var(--space-8);
  }

  .wordmark {
    font-size: var(--text-lg);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
    text-decoration: none;
    color: var(--fg);
  }

  .tag {
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
    color: var(--faint);
  }

  .nav {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .nav-link {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    text-decoration: none;
    color: var(--muted);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    transition: background 120ms ease, color 120ms ease;
  }
  .nav-link:hover {
    color: var(--fg);
    background: var(--admin-panel);
  }
  .nav-link.active {
    color: var(--fg);
    background: var(--admin-panel-strong);
  }

  .rail-foot {
    margin-top: auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding-top: var(--space-6);
  }

  .help-btn {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    background: transparent;
    border: none;
    color: var(--muted);
    cursor: pointer;
    font-family: inherit;
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
  }
  .help-btn:hover {
    color: var(--fg);
    background: var(--admin-panel);
  }
  .session {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    text-transform: lowercase;
  }

  .logout-btn {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    background: transparent;
    border: none;
    color: var(--muted);
    cursor: pointer;
    font-family: inherit;
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
  }
  .logout-btn:hover {
    color: var(--fg);
    background: var(--admin-panel);
  }

  kbd {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--muted);
    background: var(--admin-panel-strong);
    border-radius: var(--radius-sm);
    padding: 1px 6px;
    line-height: 1.4;
  }

  .main-wrap {
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .topbar {
    display: none;
  }

  .main {
    flex: 1;
  }

  .content {
    max-width: 64rem;
    margin: 0 auto;
    padding: var(--space-12) var(--space-8) var(--space-16);
  }

  .scrim {
    display: none;
  }

  .shortcuts {
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }
  .shortcuts > div {
    display: flex;
    align-items: center;
    gap: var(--space-4);
  }
  .shortcuts dt {
    display: flex;
    gap: var(--space-1);
    min-width: 5rem;
  }
  .shortcuts dd {
    margin: 0;
    color: var(--muted);
    font-size: var(--text-sm);
  }

  /* Mobile: collapse the rail into a slide-over drawer with a top bar. */
  @media (max-width: 48rem) {
    .shell {
      grid-template-columns: 1fr;
    }

    .topbar {
      display: flex;
      align-items: center;
      gap: var(--space-3);
      padding: var(--space-3) var(--space-4);
      border-bottom: 1px solid var(--hairline);
      position: sticky;
      top: 0;
      background: var(--bg);
      z-index: 50;
    }
    .menu {
      display: inline-flex;
      background: transparent;
      border: none;
      color: var(--fg);
      cursor: pointer;
      padding: var(--space-1);
    }
    .topbar-brand {
      font-size: var(--text-base);
      font-weight: var(--weight-light);
      letter-spacing: var(--tracking-wide);
      text-decoration: none;
      color: var(--fg);
    }
    .topbar-brand span {
      color: var(--faint);
      font-size: var(--text-xs);
      text-transform: uppercase;
    }

    .rail {
      position: fixed;
      top: 0;
      left: 0;
      z-index: 120;
      width: 15rem;
      background: var(--bg);
      transform: translateX(-100%);
      transition: transform 200ms ease;
    }
    .rail.open {
      transform: translateX(0);
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.28);
    }

    .scrim {
      display: block;
      position: fixed;
      inset: 0;
      z-index: 110;
      background: var(--admin-overlay);
      border: none;
    }

    .content {
      padding: var(--space-8) var(--space-4) var(--space-12);
    }
  }
</style>
