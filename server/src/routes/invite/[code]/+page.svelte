<script>
  let { data } = $props();

  let copied = $state(false);
  let copyTimer;
  const appURL = $derived(`vibes://invite/${encodeURIComponent(data.code ?? "")}`);

  async function copyCode() {
    if (!data.code) return;
    try {
      await navigator.clipboard.writeText(data.code);
      copied = true;
      clearTimeout(copyTimer);
      copyTimer = setTimeout(() => (copied = false), 2000);
    } catch {
      // Clipboard may be unavailable (blocked or insecure context). The code is
      // selectable, so the user can still copy it manually.
    }
  }
</script>

<main>
  <div class="card">
    {#if data.state !== "open"}
      <h1>This invite can't be used.</h1>
      <p class="lede">
        It may have expired, already been used, or been revoked. Ask your friend
        for a fresh link.
      </p>
    {:else}
      <p class="eyebrow">
        {#if data.inviter}{data.inviter} invited you to Vibes{:else}you're invited to Vibes{/if}
      </p>
      <h1>Open Vibes.</h1>
      <p class="lede">
        If you have the app, open this invite there. If not, download Vibes and
        paste the code in Friends after setup.
      </p>

      <div class="actions">
        <a class="primary" href={appURL}>Open in Vibes</a>
        <a href="/download">Download for Mac</a>
      </div>

      <label class="field-label" for="invite-code">invite code</label>
      <div class="code-row">
        <code id="invite-code">{data.code}</code>
        <button type="button" onclick={copyCode}>{copied ? "copied" : "copy"}</button>
      </div>
      <p class="hint">After installing, paste this code in Friends.</p>
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

  h1,
  p {
    margin: 0;
  }

  h1 {
    font-size: var(--text-xl);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
  }

  .lede {
    margin: var(--space-3) 0 var(--space-8);
    color: var(--muted);
    font-weight: var(--weight-light);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
    margin-bottom: var(--space-8);
  }

  a,
  button {
    background: var(--field-bg);
    border: none;
    border-radius: var(--radius-md);
    color: var(--fg);
    cursor: pointer;
    font: inherit;
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    padding: var(--space-3) var(--space-4);
    text-decoration: none;
  }

  a.primary {
    background: var(--accent);
    color: var(--vibe-paper);
  }

  .field-label {
    color: var(--muted);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
    margin-bottom: var(--space-2);
  }

  .code-row {
    display: flex;
    gap: var(--space-2);
    align-items: stretch;
  }

  code {
    flex: 1;
    background: var(--field-bg);
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    padding: var(--space-3);
    user-select: all;
    word-break: break-all;
  }

  .hint {
    margin-top: var(--space-3);
    color: var(--muted);
    font-size: var(--text-sm);
  }
</style>
