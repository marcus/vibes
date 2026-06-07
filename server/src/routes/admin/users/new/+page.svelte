<script>
  import { enhance } from "$app/forms";
  import {
    PageHeader,
    Section,
    Button,
    Field,
    SecretReveal,
    Icon,
  } from "$lib/components/admin/index.js";

  let { form } = $props();

  let submitting = $state(false);
  // Default to minting a link; the checkbox stays user-controlled afterward.
  let mint = $state(true);

  function onsubmit() {
    submitting = true;
    return async ({ update }) => {
      await update();
      submitting = false;
    };
  }
</script>

<svelte:head><title>New user · vibes admin</title></svelte:head>

<PageHeader
  eyebrow="users"
  title="Create a user"
  back={{ href: "/admin/users", label: "Users" }}
  description="Add a user directly. Optionally mint a one-time invite link so they can finish setup in the Mac app."
/>

{#if form?.created}
  <Section panel>
    <div class="done">
      <div class="done-mark"><Icon name="check" size={20} /></div>
      <div>
        <h2>{form.created.handle} created</h2>
        <p>{form.created.display_name}</p>
      </div>
    </div>

    {#if form.inviteUrl}
      <div class="reveal-wrap">
        <SecretReveal
          kind="link"
          title="Invite link"
          hint="Send this to the new user. It works once and is shown only here."
          value={form.inviteUrl}
        />
      </div>
    {/if}

    <div class="done-actions">
      <Button href="/admin/users/{form.created.id}" variant="primary" iconRight="chevron">Manage user</Button>
      <Button href="/admin/users/new" variant="ghost" icon="plus">Create another</Button>
    </div>
  </Section>
{:else}
  <div class="form-wrap">
    <form method="POST" use:enhance={onsubmit}>
      {#if form?.error}<p class="error" role="alert">{form.error}</p>{/if}

      <Field
        name="handle"
        label="handle"
        hint="Lowercase letters, numbers, dashes, underscores."
        value={form?.handle ?? ""}
        error={form?.field === "invalid_handle" || form?.field === "handle_taken" ? form.error : null}
        required
      />
      <Field
        name="display_name"
        label="display name"
        value={form?.display_name ?? ""}
        error={form?.field === "invalid_display_name" ? form.error : null}
        required
      />

      <label class="check">
        <input type="checkbox" name="mint" bind:checked={mint} />
        <span>
          <span class="check-title">Mint an invite link</span>
          <span class="check-sub">Reveal a one-time <code>/invite/&lt;code&gt;</code> link after creating.</span>
        </span>
      </label>

      <div class="submit">
        <Button type="submit" variant="primary" loading={submitting}>Create user</Button>
        <Button href="/admin/users" variant="ghost">Cancel</Button>
      </div>
    </form>
  </div>
{/if}

<style>
  .form-wrap {
    max-width: 28rem;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-6);
  }

  .error {
    margin: 0;
    color: var(--admin-danger);
    font-size: var(--text-sm);
  }

  .check {
    display: flex;
    gap: var(--space-3);
    cursor: pointer;
    padding: var(--space-3);
    background: var(--admin-panel);
    border-radius: var(--radius-md);
  }
  .check input {
    margin-top: 3px;
    accent-color: var(--accent);
    width: 1rem;
    height: 1rem;
    flex: none;
  }
  .check span {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .check-title {
    font-size: var(--text-sm);
  }
  .check-sub {
    color: var(--muted);
    font-size: var(--text-xs);
  }
  .check-sub code {
    font-family: var(--font-mono);
  }

  .submit {
    display: flex;
    gap: var(--space-2);
  }

  .done {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    margin-bottom: var(--space-6);
  }
  .done-mark {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 2.75rem;
    height: 2.75rem;
    border-radius: 50%;
    background: var(--accent);
    color: var(--vibe-paper);
    flex: none;
  }
  .done h2 {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
  }
  .done p {
    margin: 2px 0 0;
    color: var(--muted);
    font-size: var(--text-sm);
  }

  .done-actions {
    display: flex;
    gap: var(--space-2);
    flex-wrap: wrap;
  }
</style>
