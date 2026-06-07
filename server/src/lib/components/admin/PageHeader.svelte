<script>
  import Icon from "./Icon.svelte";

  /**
   * Page title block with an optional eyebrow, back link, description, and a
   * right-aligned actions slot. Layout comes from spacing, not rules.
   */
  let {
    title,
    eyebrow = null,
    description = null,
    back = null, // { href, label }
    actions, // snippet
  } = $props();
</script>

<header class="page-header">
  <div class="lead">
    {#if back}
      <a class="back" href={back.href}>
        <Icon name="back" size={14} />
        <span>{back.label}</span>
      </a>
    {/if}
    {#if eyebrow}<p class="eyebrow">{eyebrow}</p>{/if}
    <h1>{title}</h1>
    {#if description}<p class="description">{description}</p>{/if}
  </div>
  {#if actions}
    <div class="actions">{@render actions()}</div>
  {/if}
</header>

<style>
  .page-header {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: var(--space-6);
    flex-wrap: wrap;
    margin-bottom: var(--space-8);
  }

  .lead {
    min-width: 0;
  }

  .back {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    color: var(--muted);
    text-decoration: none;
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    margin-bottom: var(--space-3);
    transition: color 120ms ease;
  }
  .back:hover {
    color: var(--fg);
  }

  .eyebrow {
    margin: 0 0 var(--space-2);
    color: var(--muted);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    text-transform: lowercase;
  }

  h1 {
    margin: 0;
    font-size: var(--text-xl);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
    line-height: var(--leading-tight);
  }

  .description {
    margin: var(--space-3) 0 0;
    color: var(--muted);
    font-weight: var(--weight-light);
    max-width: 52ch;
  }

  .actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }
</style>
