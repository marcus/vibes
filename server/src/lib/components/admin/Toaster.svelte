<script>
  import { fly, fade } from "svelte/transition";
  import { flip } from "svelte/animate";
  import Icon from "./Icon.svelte";
  import { toastStore, dismissToast } from "./toasts.svelte.js";

  const ICON = { success: "check", error: "close", info: "dot" };
</script>

<div class="toaster" aria-live="polite" aria-atomic="false">
  {#each toastStore.items as toast (toast.id)}
    <div
      class="toast {toast.tone}"
      role="status"
      in:fly={{ y: 12, duration: 220 }}
      out:fade={{ duration: 160 }}
      animate:flip={{ duration: 180 }}
    >
      <span class="icon"><Icon name={ICON[toast.tone] ?? "dot"} size={14} /></span>
      <span class="message">{toast.message}</span>
      <button type="button" class="dismiss" onclick={() => dismissToast(toast.id)} aria-label="Dismiss">
        <Icon name="close" size={13} />
      </button>
    </div>
  {/each}
</div>

<style>
  .toaster {
    position: fixed;
    bottom: var(--space-6);
    right: var(--space-6);
    z-index: 200;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    pointer-events: none;
    max-width: min(24rem, calc(100vw - 2 * var(--space-6)));
  }

  .toast {
    pointer-events: auto;
    display: flex;
    align-items: center;
    gap: var(--space-3);
    background: var(--bg);
    color: var(--fg);
    border-radius: var(--radius-md);
    padding: var(--space-3) var(--space-3) var(--space-3) var(--space-4);
    box-shadow: 0 1px 0 var(--hairline), 0 8px 24px rgba(0, 0, 0, 0.14);
  }

  .icon {
    display: inline-flex;
    color: var(--muted);
    flex: none;
  }
  .toast.success .icon {
    color: var(--accent);
  }
  .toast.error .icon {
    color: var(--admin-danger);
  }

  .message {
    flex: 1;
    font-size: var(--text-sm);
    line-height: var(--leading-normal);
  }

  .dismiss {
    display: inline-flex;
    background: transparent;
    border: none;
    color: var(--faint);
    cursor: pointer;
    padding: 2px;
    border-radius: var(--radius-sm);
    flex: none;
  }
  .dismiss:hover {
    color: var(--fg);
  }
</style>
