<script>
  import Icon from "./Icon.svelte";

  /**
   * Copies `text` to the clipboard and confirms inline for a moment. Used for
   * ids, tokens, and invite links. Falls back silently if the clipboard API is
   * unavailable.
   */
  let { text, label = "copy", iconOnly = false, size = "sm" } = $props();

  let copied = $state(false);
  let timer = null;

  async function copy() {
    try {
      await navigator.clipboard.writeText(String(text ?? ""));
      copied = true;
      clearTimeout(timer);
      timer = setTimeout(() => (copied = false), 1600);
    } catch {
      // Clipboard blocked (insecure context / denied) — leave state untouched.
    }
  }
</script>

<button
  type="button"
  class="copy {size}"
  class:copied
  class:icon-only={iconOnly}
  onclick={copy}
  title={copied ? "copied" : label}
  aria-label={label}
>
  <Icon name={copied ? "check" : "copy"} size={size === "sm" ? 13 : 15} />
  {#if !iconOnly}<span>{copied ? "copied" : label}</span>{/if}
</button>

<style>
  .copy {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    background: transparent;
    border: none;
    border-radius: var(--radius-sm);
    color: var(--muted);
    cursor: pointer;
    font-family: inherit;
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    padding: var(--space-1) var(--space-2);
    transition: color 120ms ease, background 120ms ease;
  }

  .copy:hover {
    color: var(--fg);
    background: var(--admin-panel);
  }
  .copy:focus-visible {
    outline: 2px solid var(--admin-focus);
    outline-offset: 1px;
  }

  .copy.copied {
    color: var(--accent);
  }

  .icon-only {
    padding: var(--space-1);
  }
</style>
