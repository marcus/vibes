<script>
  import { enhance } from "$app/forms";

  let { data, form } = $props();

  let copied = $state(false);

  async function copyToken() {
    if (!form?.token) return;
    await navigator.clipboard.writeText(form.token);
    copied = true;
  }
</script>

<main>
  <div class="card">
    {#if form?.accepted}
      <p class="eyebrow">welcome, {form.handle}</p>
      <h1>You're in.</h1>
      <p class="lede">
        Copy your token now — it is shown once. Keep it somewhere safe, then add
        it during first launch in the Vibes app.
      </p>

      <label class="field-label" for="token">your token</label>
      <div class="token-row">
        <code id="token" class="token">{form.token}</code>
        <button type="button" onclick={copyToken}>{copied ? "copied" : "copy"}</button>
      </div>

      <details class="config">
        <summary>config snippet</summary>
        <pre>{form.config}</pre>
      </details>
    {:else if data.state !== "open"}
      <h1>This invite can't be used.</h1>
      <p class="lede">
        It may have expired, already been used, or been revoked. Ask your friend
        for a fresh link.
      </p>
    {:else}
      <p class="eyebrow">
        {#if data.inviter}{data.inviter} invited you{:else}you're invited{/if}
      </p>
      <h1>Join Vibes.</h1>
      <p class="lede">
        Pick a handle your friends will see, then finish setup in the app.
      </p>

      {#if form?.error}
        <p class="error">{form.error}</p>
      {/if}

      <form method="POST" use:enhance>
        <label class="field-label" for="handle">handle</label>
        <input
          id="handle"
          name="handle"
          autocomplete="off"
          autocapitalize="off"
          spellcheck="false"
          value={form?.handle ?? ""}
          required
        />

        <label class="field-label" for="display_name">display name</label>
        <input
          id="display_name"
          name="display_name"
          value={form?.display_name ?? ""}
          required
        />

        <label class="field-label" for="device_label">device <span class="optional">optional</span></label>
        <input
          id="device_label"
          name="device_label"
          placeholder="MacBook"
          value={form?.device_label ?? ""}
        />

        <button type="submit" class="primary">Accept invite</button>
      </form>
    {/if}
  </div>
</main>

<style>
  main {
    min-height: 100dvh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-8);
  }

  .card {
    width: 100%;
    max-width: 26rem;
    display: flex;
    flex-direction: column;
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
  }

  .lede {
    margin: var(--space-3) 0 var(--space-8);
    color: var(--muted);
    font-weight: var(--weight-light);
  }

  form {
    display: flex;
    flex-direction: column;
  }

  .field-label {
    font-size: var(--text-sm);
    color: var(--muted);
    margin-bottom: var(--space-2);
    letter-spacing: var(--tracking-wide);
  }

  .optional {
    color: var(--faint);
  }

  input {
    background: var(--field-bg);
    border: none;
    border-radius: var(--radius-md);
    color: var(--fg);
    font-family: inherit;
    font-size: var(--text-base);
    padding: var(--space-3);
    margin-bottom: var(--space-6);
  }

  input:focus {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }

  button {
    background: var(--field-bg);
    border: none;
    border-radius: var(--radius-md);
    color: var(--fg);
    cursor: pointer;
    font-size: var(--text-sm);
    padding: var(--space-3) var(--space-4);
    letter-spacing: var(--tracking-wide);
  }

  button.primary {
    background: var(--accent);
    color: var(--vibe-paper);
    font-size: var(--text-base);
    padding: var(--space-3);
  }

  .token-row {
    display: flex;
    gap: var(--space-2);
    align-items: stretch;
  }

  .token {
    flex: 1;
    background: var(--field-bg);
    border-radius: var(--radius-md);
    padding: var(--space-3);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    word-break: break-all;
    user-select: all;
  }

  .config {
    margin-top: var(--space-6);
  }

  .config summary {
    color: var(--muted);
    cursor: pointer;
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
  }

  .config pre {
    background: var(--field-bg);
    border-radius: var(--radius-md);
    padding: var(--space-4);
    margin-top: var(--space-3);
    overflow-x: auto;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
  }

  .error {
    margin: 0 0 var(--space-4);
    color: var(--accent);
    font-size: var(--text-sm);
  }
</style>
