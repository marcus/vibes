<script>
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import Icon from "./Icon.svelte";

  /**
   * Server-backed search box. Edits debounce into a URL update so the page load
   * re-queries, keeping focus and scroll. Press "/" anywhere to focus it (wired
   * in AdminShell); Escape clears.
   */
  let { param = "search", placeholder = "Search", value = "" } = $props();

  let current = $state(value);
  let input;
  let timer = null;

  $effect(() => {
    // Keep in sync if the URL changes underneath us (e.g. back/forward).
    current = value;
  });

  function commit(next) {
    const url = new URL($page.url);
    if (next) url.searchParams.set(param, next);
    else url.searchParams.delete(param);
    goto(`${url.pathname}${url.search}`, {
      keepFocus: true,
      noScroll: true,
      replaceState: true,
    });
  }

  function onInput() {
    clearTimeout(timer);
    timer = setTimeout(() => commit(current.trim()), 220);
  }

  function clear() {
    current = "";
    clearTimeout(timer);
    commit("");
    input?.focus();
  }

  function onKeydown(event) {
    if (event.key === "Escape" && current) {
      event.preventDefault();
      clear();
    }
  }
</script>

<div class="search" data-search>
  <Icon name="search" size={15} class="search-glyph" />
  <input
    bind:this={input}
    bind:value={current}
    {placeholder}
    type="search"
    autocomplete="off"
    autocapitalize="off"
    spellcheck="false"
    aria-label={placeholder}
    oninput={onInput}
    onkeydown={onKeydown}
  />
  {#if current}
    <button type="button" class="clear" onclick={clear} aria-label="Clear search">
      <Icon name="close" size={13} />
    </button>
  {:else}
    <kbd class="hint">/</kbd>
  {/if}
</div>

<style>
  .search {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    background: var(--field-bg);
    border-radius: var(--radius-md);
    padding: 0 var(--space-3);
    height: 2.25rem;
    color: var(--muted);
    min-width: 14rem;
    transition: outline-color 100ms ease;
  }

  .search:focus-within {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }

  input {
    flex: 1;
    background: transparent;
    border: none;
    color: var(--fg);
    font-family: inherit;
    font-size: var(--text-sm);
    padding: 0;
    min-width: 0;
  }
  input:focus {
    outline: none;
  }
  input::-webkit-search-cancel-button {
    display: none;
  }

  .clear {
    display: inline-flex;
    background: transparent;
    border: none;
    color: var(--muted);
    cursor: pointer;
    padding: 2px;
    border-radius: var(--radius-sm);
  }
  .clear:hover {
    color: var(--fg);
  }

  .hint {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--faint);
    background: var(--admin-panel-strong);
    border-radius: var(--radius-sm);
    padding: 1px 6px;
    line-height: 1.4;
  }
</style>
