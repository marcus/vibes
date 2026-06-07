<script>
  /**
   * A single headline metric for the dashboard. The number leads in a light,
   * tabular weight; the label sits quietly beneath. Optional `parts` render a
   * small breakdown row (e.g. invite states) under the figure.
   */
  let {
    label,
    value,
    sub = null,
    parts = null, // [{ label, value }]
    href = null,
    accent = false,
  } = $props();
</script>

<svelte:element
  this={href ? "a" : "div"}
  href={href ?? undefined}
  class="stat"
  class:linked={href}
  class:accent
>
  <div class="value">{value}</div>
  <div class="label">{label}</div>
  {#if sub}<div class="sub">{sub}</div>{/if}
  {#if parts}
    <dl class="parts">
      {#each parts as part (part.label)}
        <div class="part">
          <dt>{part.label}</dt>
          <dd>{part.value}</dd>
        </div>
      {/each}
    </dl>
  {/if}
</svelte:element>

<style>
  .stat {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    padding: var(--space-6);
    background: var(--admin-panel);
    border-radius: var(--radius-md);
    text-decoration: none;
    color: inherit;
    transition: background 140ms ease, transform 100ms ease;
  }

  .stat.linked {
    cursor: pointer;
  }
  .stat.linked:hover {
    background: var(--admin-panel-strong);
  }
  .stat.linked:active {
    transform: translateY(0.5px);
  }
  .stat.linked:focus-visible {
    outline: 2px solid var(--admin-focus);
    outline-offset: 2px;
  }

  .value {
    font-size: var(--text-2xl);
    font-weight: var(--weight-light);
    line-height: 1;
    letter-spacing: -0.01em;
    font-variant-numeric: tabular-nums;
  }

  .accent .value {
    color: var(--accent);
  }

  .label {
    margin-top: var(--space-2);
    color: var(--muted);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    text-transform: lowercase;
  }

  .sub {
    color: var(--faint);
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
  }

  .parts {
    margin: var(--space-3) 0 0;
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1) var(--space-4);
  }

  .part {
    display: flex;
    align-items: baseline;
    gap: var(--space-1);
  }

  .part dt {
    color: var(--faint);
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
  }

  .part dd {
    margin: 0;
    font-size: var(--text-sm);
    font-variant-numeric: tabular-nums;
    color: var(--muted);
  }
</style>
