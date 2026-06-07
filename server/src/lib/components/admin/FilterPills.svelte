<script>
  import { page } from "$app/stores";

  /**
   * Segmented filter rendered as links so it works without JS and keeps URLs
   * shareable. Each option may carry a count. The active pill is derived from
   * the current URL param.
   */
  let { param = "state", options, current = null } = $props();

  let active = $derived(current ?? $page.url.searchParams.get(param) ?? options[0]?.value);

  function hrefFor(value) {
    const url = new URL($page.url);
    if (value === options[0]?.value) url.searchParams.delete(param);
    else url.searchParams.set(param, value);
    return `${url.pathname}${url.search}`;
  }
</script>

<div class="pills" role="tablist">
  {#each options as opt (opt.value)}
    <a
      class="pill"
      class:active={active === opt.value}
      href={hrefFor(opt.value)}
      role="tab"
      aria-selected={active === opt.value}
      data-sveltekit-noscroll
    >
      <span>{opt.label}</span>
      {#if opt.count != null}<span class="count">{opt.count}</span>{/if}
    </a>
  {/each}
</div>

<style>
  .pills {
    display: inline-flex;
    gap: var(--space-1);
    background: var(--admin-panel);
    border-radius: var(--radius-md);
    padding: var(--space-1);
  }

  .pill {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    text-decoration: none;
    color: var(--muted);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    padding: var(--space-1) var(--space-3);
    border-radius: var(--radius-sm);
    transition: background 120ms ease, color 120ms ease;
  }

  .pill:hover {
    color: var(--fg);
  }

  .pill.active {
    background: var(--bg);
    color: var(--fg);
  }

  .count {
    font-variant-numeric: tabular-nums;
    font-size: var(--text-xs);
    color: var(--faint);
  }
  .pill.active .count {
    color: var(--muted);
  }
</style>
