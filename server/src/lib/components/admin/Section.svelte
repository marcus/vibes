<script>
  /**
   * A titled content panel. Quiet by default (no surface); set `panel` for a
   * faint raised background where a group genuinely needs to read as one block.
   */
  let {
    title = null,
    description = null,
    count = null,
    panel = false,
    danger = false,
    actions, // snippet
    children,
  } = $props();
</script>

<section class="section" class:panel class:danger>
  {#if title || actions}
    <div class="head">
      <div class="titles">
        {#if title}
          <h2>
            {title}{#if count != null}<span class="count">{count}</span>{/if}
          </h2>
        {/if}
        {#if description}<p class="description">{description}</p>{/if}
      </div>
      {#if actions}<div class="actions">{@render actions()}</div>{/if}
    </div>
  {/if}
  <div class="section-body">{@render children?.()}</div>
</section>

<style>
  .section {
    display: block;
  }

  .section.panel {
    background: var(--admin-panel);
    border-radius: var(--radius-md);
    padding: var(--space-6);
  }

  .section.danger {
    background: var(--admin-danger-wash);
    border-radius: var(--radius-md);
    padding: var(--space-6);
  }

  .head {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: var(--space-4);
    margin-bottom: var(--space-4);
  }

  .titles {
    min-width: 0;
  }

  h2 {
    margin: 0;
    font-size: var(--text-sm);
    font-weight: var(--weight-medium);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
    color: var(--muted);
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
  }

  .count {
    color: var(--faint);
    font-weight: var(--weight-regular);
  }

  .description {
    margin: var(--space-2) 0 0;
    color: var(--muted);
    font-size: var(--text-sm);
    font-weight: var(--weight-light);
  }

  .actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex: none;
  }
</style>
