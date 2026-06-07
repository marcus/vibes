<script>
  import Icon from "./Icon.svelte";

  /**
   * One button to rule the admin. Renders an <a> when `href` is set, otherwise a
   * <button>. Variants map to the house style: `primary` and `danger` are the
   * only accent-filled treatments; everything else is quiet.
   */
  let {
    variant = "default", // default | primary | danger | ghost | subtle
    size = "md", // sm | md
    type = "button",
    href = null,
    icon = null, // icon name string
    iconRight = null,
    loading = false,
    disabled = false,
    full = false,
    title = null,
    name = null,
    value = null,
    formaction = null,
    onclick = null,
    children,
    class: klass = "",
  } = $props();

  let isDisabled = $derived(disabled || loading);
</script>

{#if href}
  <a
    class="btn {variant} {size} {full ? 'full' : ''} {klass}"
    class:disabled={isDisabled}
    href={isDisabled ? undefined : href}
    aria-disabled={isDisabled}
    {title}
    {onclick}
  >
    {#if icon}<Icon name={icon} size={size === "sm" ? 14 : 16} />{/if}
    <span class="label">{@render children?.()}</span>
    {#if iconRight}<Icon name={iconRight} size={size === "sm" ? 14 : 16} />{/if}
  </a>
{:else}
  <button
    class="btn {variant} {size} {full ? 'full' : ''} {klass}"
    class:loading
    {type}
    {name}
    {value}
    {formaction}
    {title}
    disabled={isDisabled}
    {onclick}
  >
    {#if loading}<span class="spinner" aria-hidden="true"></span>{/if}
    {#if icon && !loading}<Icon name={icon} size={size === "sm" ? 14 : 16} />{/if}
    <span class="label">{@render children?.()}</span>
    {#if iconRight && !loading}<Icon name={iconRight} size={size === "sm" ? 14 : 16} />{/if}
  </button>
{/if}

<style>
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    font-family: inherit;
    font-size: var(--text-sm);
    font-weight: var(--weight-regular);
    letter-spacing: var(--tracking-wide);
    line-height: 1;
    color: var(--fg);
    background: var(--admin-panel-strong);
    border: none;
    border-radius: var(--radius-md);
    padding: 0 var(--space-4);
    height: 2.25rem;
    cursor: pointer;
    text-decoration: none;
    white-space: nowrap;
    transition:
      background 120ms ease,
      color 120ms ease,
      transform 80ms ease,
      opacity 120ms ease;
  }

  .btn:hover {
    background: var(--admin-panel-strong);
    filter: brightness(0.97);
  }
  @media (prefers-color-scheme: dark) {
    .btn:hover {
      filter: brightness(1.25);
    }
  }

  .btn:active {
    transform: translateY(0.5px) scale(0.99);
  }

  .btn:focus-visible {
    outline: 2px solid var(--admin-focus);
    outline-offset: 2px;
  }

  .btn.sm {
    height: 1.875rem;
    padding: 0 var(--space-3);
    font-size: var(--text-xs);
  }

  .btn.full {
    width: 100%;
  }

  /* Quiet, text-forward variants */
  .btn.ghost {
    background: transparent;
  }
  .btn.ghost:hover {
    background: var(--admin-panel);
    filter: none;
  }

  .btn.subtle {
    background: var(--field-bg);
  }

  /* Accent — reserved for the single primary action */
  .btn.primary {
    background: var(--accent);
    color: var(--vibe-paper);
  }
  .btn.primary:hover {
    filter: brightness(1.06);
  }

  /* Destructive — accent text by default; the typed-confirm uses fill */
  .btn.danger {
    background: transparent;
    color: var(--admin-danger);
  }
  .btn.danger:hover {
    background: var(--admin-danger-wash);
    filter: none;
  }

  .btn:disabled,
  .btn.disabled {
    opacity: 0.45;
    cursor: not-allowed;
    pointer-events: none;
  }

  .label:empty {
    display: none;
  }

  .spinner {
    width: 0.85em;
    height: 0.85em;
    border-radius: 50%;
    border: 1.5px solid currentColor;
    border-top-color: transparent;
    animation: spin 0.6s linear infinite;
    opacity: 0.8;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
