<script>
  import Icon from "./Icon.svelte";

  /**
   * Calm placeholder for empty tables and lists. Lets emptiness do the work — a
   * faint glyph, a line of copy, and an optional action.
   */
  let { icon = "dot", title, description = null, actions } = $props();
</script>

<div class="empty">
  <div class="glyph"><Icon name={icon} size={22} stroke={1.3} /></div>
  <p class="title">{title}</p>
  {#if description}<p class="description">{description}</p>{/if}
  {#if actions}<div class="actions">{@render actions()}</div>{/if}
</div>

<style>
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: var(--space-2);
    padding: var(--space-12) var(--space-6);
    color: var(--muted);
  }

  .glyph {
    color: var(--faint);
    margin-bottom: var(--space-1);
  }

  .title {
    margin: 0;
    font-size: var(--text-base);
    font-weight: var(--weight-light);
    color: var(--fg);
  }

  .description {
    margin: 0;
    font-size: var(--text-sm);
    font-weight: var(--weight-light);
    max-width: 38ch;
  }

  .actions {
    margin-top: var(--space-4);
  }
</style>
