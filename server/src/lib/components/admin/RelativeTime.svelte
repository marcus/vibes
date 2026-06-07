<script>
  import { relativeTime, formatDate, formatDateTime } from "$lib/format.js";

  /**
   * Renders a timestamp as a relative phrase ("3 minutes ago") with the absolute
   * value in the title for hover. To avoid an SSR/client hydration mismatch (the
   * server and browser clocks differ), the absolute form renders first and the
   * relative form swaps in after mount.
   */
  let { value, dateOnly = false, fallback = "—" } = $props();

  let mounted = $state(false);
  $effect(() => {
    mounted = true;
    // Re-tick every 30s so "just now" ages gracefully on long-lived pages.
    const id = setInterval(() => {
      tick = Date.now();
    }, 30_000);
    return () => clearInterval(id);
  });
  let tick = $state(0);

  let absolute = $derived(dateOnly ? formatDate(value) : formatDateTime(value));
  let display = $derived(
    !value ? fallback : mounted ? (relativeTime(value, tick || Date.now()) || absolute) : absolute,
  );
</script>

{#if value}
  <time datetime={String(value)} title={absolute}>{display}</time>
{:else}
  <span class="fallback">{fallback}</span>
{/if}

<style>
  time {
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .fallback {
    color: var(--faint);
  }
</style>
