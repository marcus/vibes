<script>
  import { fade, scale } from "svelte/transition";
  import Icon from "./Icon.svelte";

  /**
   * Accessible base modal: backdrop + centered panel, Escape to close, click
   * outside to dismiss, focus moved in on open and restored on close, and a
   * simple focus trap so Tab stays within the dialog.
   */
  let {
    open = $bindable(false),
    title = null,
    description = null,
    size = "md", // sm | md
    onclose = null,
    children,
    footer,
  } = $props();

  let panel = $state(null);
  let restoreFocus = null;

  function close() {
    open = false;
    onclose?.();
  }

  function onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      close();
      return;
    }
    if (event.key === "Tab" && panel) {
      const focusable = panel.querySelectorAll(
        'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])',
      );
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  $effect(() => {
    if (open) {
      restoreFocus = document.activeElement;
      // Defer so the panel is mounted before we move focus into it.
      queueMicrotask(() => {
        const target = panel?.querySelector(
          'input, textarea, select, button, a[href], [tabindex]:not([tabindex="-1"])',
        );
        target?.focus();
      });
      const prev = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      return () => {
        document.body.style.overflow = prev;
        if (restoreFocus instanceof HTMLElement) restoreFocus.focus();
      };
    }
  });
</script>

<svelte:window onkeydown={open ? onKeydown : undefined} />

{#if open}
  <div class="backdrop" transition:fade={{ duration: 160 }} onclick={close} aria-hidden="true"></div>
  <div class="layer" role="presentation">
    <div
      class="panel {size}"
      bind:this={panel}
      role="dialog"
      aria-modal="true"
      aria-label={title ?? "Dialog"}
      transition:scale={{ duration: 180, start: 0.97, opacity: 0 }}
    >
      {#if title}
        <div class="head">
          <div>
            <h2>{title}</h2>
            {#if description}<p class="description">{description}</p>{/if}
          </div>
          <button type="button" class="x" onclick={close} aria-label="Close">
            <Icon name="close" size={16} />
          </button>
        </div>
      {/if}
      <div class="content">{@render children?.()}</div>
      {#if footer}<div class="foot">{@render footer()}</div>{/if}
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: var(--admin-overlay);
    z-index: 150;
  }

  .layer {
    position: fixed;
    inset: 0;
    z-index: 151;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-6);
    pointer-events: none;
  }

  .panel {
    pointer-events: auto;
    width: 100%;
    max-width: 30rem;
    max-height: calc(100dvh - 2 * var(--space-8));
    overflow-y: auto;
    background: var(--bg);
    border-radius: var(--radius-md);
    padding: var(--space-6);
    box-shadow: 0 1px 0 var(--hairline), 0 24px 60px rgba(0, 0, 0, 0.28);
  }

  .panel.sm {
    max-width: 24rem;
  }

  .head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
    margin-bottom: var(--space-4);
  }

  h2 {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
  }

  .description {
    margin: var(--space-2) 0 0;
    color: var(--muted);
    font-size: var(--text-sm);
    font-weight: var(--weight-light);
    line-height: var(--leading-normal);
  }

  .x {
    display: inline-flex;
    background: transparent;
    border: none;
    color: var(--muted);
    cursor: pointer;
    padding: var(--space-1);
    border-radius: var(--radius-sm);
    margin: calc(-1 * var(--space-1));
    flex: none;
  }
  .x:hover {
    color: var(--fg);
    background: var(--admin-panel);
  }

  .foot {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-top: var(--space-6);
  }
</style>
