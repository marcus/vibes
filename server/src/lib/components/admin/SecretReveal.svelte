<script>
  import { slide } from "svelte/transition";
  import Icon from "./Icon.svelte";
  import CopyButton from "./CopyButton.svelte";

  /**
   * One-time reveal for a freshly minted secret (bearer token or invite link).
   * The value is shown exactly once in an action response and never re-rendered,
   * matching how the public accept page treats tokens. Dismissing clears it.
   */
  let {
    title = "Copy this now",
    hint = "It is shown once and cannot be retrieved later.",
    value,
    kind = "token", // token | link
    ondismiss = null,
  } = $props();
</script>

<div class="reveal" transition:slide={{ duration: 200 }}>
  <div class="bar"></div>
  <div class="inner">
    <div class="top">
      <div class="title">
        <Icon name={kind === "link" ? "link" : "key"} size={15} />
        <span>{title}</span>
      </div>
      {#if ondismiss}
        <button type="button" class="dismiss" onclick={ondismiss} aria-label="Dismiss">
          <Icon name="close" size={14} />
        </button>
      {/if}
    </div>

    <div class="value-row">
      <code class="value">{value}</code>
      <div class="value-actions">
        <CopyButton text={value} label="copy" size="md" />
        {#if kind === "link"}
          <a class="open" href={value} target="_blank" rel="noreferrer noopener">
            <Icon name="link" size={13} /> open
          </a>
        {/if}
      </div>
    </div>

    <p class="hint">{hint}</p>
  </div>
</div>

<style>
  .reveal {
    display: flex;
    background: var(--admin-panel-strong);
    border-radius: var(--radius-md);
    overflow: hidden;
    margin-bottom: var(--space-6);
  }

  .bar {
    width: 3px;
    background: var(--accent);
    flex: none;
  }

  .inner {
    flex: 1;
    min-width: 0;
    padding: var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
  }

  .title {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    color: var(--fg);
  }

  .dismiss {
    display: inline-flex;
    background: transparent;
    border: none;
    color: var(--muted);
    cursor: pointer;
    padding: 2px;
    border-radius: var(--radius-sm);
  }
  .dismiss:hover {
    color: var(--fg);
  }

  .value-row {
    display: flex;
    align-items: stretch;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .value {
    flex: 1;
    min-width: 12rem;
    background: var(--bg);
    border-radius: var(--radius-md);
    padding: var(--space-3);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    word-break: break-all;
    user-select: all;
  }

  .value-actions {
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  .open {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    color: var(--muted);
    text-decoration: none;
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-sm);
  }
  .open:hover {
    color: var(--fg);
    background: var(--admin-panel);
  }

  .hint {
    margin: 0;
    color: var(--muted);
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
  }
</style>
