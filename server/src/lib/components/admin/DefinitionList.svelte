<script>
  /**
   * Key/value profile display. Pass `items` as [{ term, value, mono }] or use
   * the children snippet for custom rows. Terms are quiet; values lead.
   */
  let { items = null, children } = $props();
</script>

<dl class="def">
  {#if items}
    {#each items as item (item.term)}
      <div class="row">
        <dt>{item.term}</dt>
        <dd class:mono={item.mono}>{item.value}</dd>
      </div>
    {/each}
  {:else}
    {@render children?.()}
  {/if}
</dl>

<style>
  .def {
    margin: 0;
    display: grid;
    grid-template-columns: minmax(7rem, max-content) 1fr;
    gap: var(--space-3) var(--space-6);
  }

  :global(.def .row) {
    display: contents;
  }

  :global(.def dt) {
    color: var(--muted);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
  }

  :global(.def dd) {
    margin: 0;
    font-size: var(--text-sm);
    overflow-wrap: anywhere;
  }

  :global(.def dd.mono) {
    font-family: var(--font-mono);
    color: var(--muted);
  }
</style>
