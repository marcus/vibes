<script>
  import { enhance } from "$app/forms";
  import { invalidateAll } from "$app/navigation";
  import {
    PageHeader,
    Section,
    Button,
    Field,
    Table,
    StateBadge,
    DefinitionList,
    EmptyState,
    RelativeTime,
    CopyButton,
    SecretReveal,
    Modal,
    ConfirmDialog,
    pushToast,
  } from "$lib/components/admin/index.js";
  import { shortId } from "$lib/format.js";

  let { data } = $props();
  let detail = $derived(data.detail);
  let user = $derived(detail.profile);

  let revealSecret = $state(null);
  let tokenModalOpen = $state(false);
  let tokenLabel = $state("");
  let tokenSubmitting = $state(false);

  let deleteOpen = $state(false);

  // Shared confirmation for the various revoke/remove actions.
  let confirmOpen = $state(false);
  let confirm = $state(null);

  function askConfirm(config) {
    confirm = config;
    confirmOpen = true;
  }

  // Enhance handler that surfaces a one-time secret from the action response.
  function captureSecret(onDone) {
    return () => {
      return async ({ result }) => {
        if (result.type === "success" && result.data?.secret) {
          revealSecret = result.data.secret;
          onDone?.();
          pushToast(`${result.data.secret.title} created`, { tone: "success" });
          await invalidateAll();
        } else if (result.type === "failure") {
          pushToast(result.data?.error ?? "Something went wrong.", { tone: "error" });
        }
      };
    };
  }

  // Enhance handler for simple state changes (disable/enable).
  function simpleAction(message) {
    return () => {
      return async ({ result }) => {
        if (result.type === "success") {
          pushToast(message, { tone: "success" });
          await invalidateAll();
        } else if (result.type === "failure") {
          pushToast(result.data?.error ?? "Something went wrong.", { tone: "error" });
        }
      };
    };
  }

  function mintTokenSubmit() {
    tokenSubmitting = true;
    const handler = captureSecret(() => {
      tokenModalOpen = false;
      tokenLabel = "";
    });
    const inner = handler();
    return async (event) => {
      await inner(event);
      tokenSubmitting = false;
    };
  }
</script>

<svelte:head><title>{user.handle} · vibes admin</title></svelte:head>

<PageHeader
  eyebrow="user"
  title={user.display_name}
  back={{ href: "/admin/users", label: "Users" }}
>
  {#snippet actions()}
    <div class="header-status">
      <StateBadge state={user.disabled ? "disabled" : detail.presence} />
    </div>
    {#if user.disabled}
      <form method="POST" action="?/enable" use:enhance={simpleAction("User enabled")}>
        <Button type="submit" variant="subtle" icon="power">Enable</Button>
      </form>
    {:else}
      <form method="POST" action="?/disable" use:enhance={simpleAction("User disabled")}>
        <Button type="submit" variant="subtle" icon="power">Disable</Button>
      </form>
    {/if}
  {/snippet}
</PageHeader>

{#if revealSecret}
  <SecretReveal
    kind={revealSecret.kind}
    title={revealSecret.title}
    value={revealSecret.value}
    hint={revealSecret.kind === "link"
      ? "Send this to the user. It works once and is shown only here."
      : "Store it now — the raw token is shown once and cannot be retrieved later."}
    ondismiss={() => (revealSecret = null)}
  />
{/if}

<div class="grid">
  <Section title="Profile">
    <DefinitionList>
      <div class="row"><dt>Handle</dt><dd>{user.handle}</dd></div>
      <div class="row"><dt>Display name</dt><dd>{user.display_name}</dd></div>
      <div class="row"><dt>Timezone</dt><dd class="mono">{user.timezone ?? "—"}</dd></div>
      <div class="row">
        <dt>User id</dt>
        <dd class="mono id-cell">
          <span title={user.id}>{shortId(user.id, 12)}</span>
          <CopyButton text={user.id} iconOnly label="Copy user id" />
        </dd>
      </div>
      <div class="row"><dt>Status</dt><dd>
        {#if user.disabled}
          <StateBadge state="disabled" /> <span class="since">since <RelativeTime value={user.disabled_at} /></span>
        {:else}
          <StateBadge state="enabled" />
        {/if}
      </dd></div>
      <div class="row"><dt>Joined</dt><dd><RelativeTime value={user.created_at} /></dd></div>
      <div class="row"><dt>Updated</dt><dd><RelativeTime value={user.updated_at} /></dd></div>
      <div class="row"><dt>Signed up via</dt><dd>
        {#if detail.origin}
          invite from <span class="strong">{detail.origin.inviter_handle}</span>
          <span class="since">· <RelativeTime value={detail.origin.accepted_at} /></span>
        {:else}
          <span class="muted">direct / bootstrap</span>
        {/if}
      </dd></div>
    </DefinitionList>
  </Section>

  <Section title="Presence & devices" count={detail.counts.devices}>
    {#if detail.devices.length}
      <Table>
        <thead>
          <tr>
            <th>Device</th>
            <th>Mode</th>
            <th>Day</th>
            <th>Timezone</th>
            <th>Updated</th>
            <th>Received</th>
          </tr>
        </thead>
        <tbody>
          {#each detail.devices as device (device.device_id)}
            <tr>
              <td>
                {device.device_label ?? "—"}
                <div class="sub mono">{shortId(device.device_id, 14)}</div>
              </td>
              <td><StateBadge state={device.mode} /></td>
              <td class="mono">{device.client_day}</td>
              <td class="mono">{device.day_timezone ?? "—"}</td>
              <td><RelativeTime value={device.updated_at} /></td>
              <td><RelativeTime value={device.server_received_at} /></td>
            </tr>
          {/each}
        </tbody>
      </Table>
    {:else}
      <EmptyState icon="device" title="No devices" description="This user has not published any status yet." />
    {/if}
  </Section>

  <Section title="Tokens" count={detail.counts.tokens_active}>
    {#snippet actions()}
      <Button variant="subtle" size="sm" icon="key" onclick={() => (tokenModalOpen = true)}>Mint token</Button>
    {/snippet}
    {#if detail.tokens.length}
      <Table>
        <thead>
          <tr>
            <th>Label</th>
            <th>Created</th>
            <th>Last used</th>
            <th>State</th>
            <th class="shrink"></th>
          </tr>
        </thead>
        <tbody>
          {#each detail.tokens as token (token.id)}
            <tr>
              <td>{token.label ?? "—"}</td>
              <td><RelativeTime value={token.created_at} /></td>
              <td><RelativeTime value={token.last_used_at} fallback="never" /></td>
              <td><StateBadge state={token.revoked ? "revoked" : "active"} /></td>
              <td class="shrink">
                <div class="cell-actions">
                  {#if !token.revoked}
                    <Button
                      variant="danger"
                      size="sm"
                      onclick={() =>
                        askConfirm({
                          action: "?/revokeToken",
                          title: "Revoke token?",
                          description: `“${token.label ?? shortId(token.id)}” will stop working immediately. This cannot be undone.`,
                          confirmLabel: "Revoke token",
                          successMessage: "Token revoked",
                          hidden: { token_id: token.id },
                        })}
                    >Revoke</Button>
                  {/if}
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </Table>
    {:else}
      <EmptyState icon="key" title="No tokens" description="Mint a bearer token to let this user’s device authenticate.">
        {#snippet actions()}
          <Button variant="subtle" size="sm" icon="key" onclick={() => (tokenModalOpen = true)}>Mint token</Button>
        {/snippet}
      </EmptyState>
    {/if}
  </Section>

  <Section title="Invites" count={detail.counts.invites}>
    {#snippet actions()}
      <form method="POST" action="?/createInvite" use:enhance={captureSecret()}>
        <Button type="submit" variant="subtle" size="sm" icon="invites">Create invite</Button>
      </form>
    {/snippet}
    {#if detail.invites.length}
      <Table>
        <thead>
          <tr>
            <th>State</th>
            <th>Created</th>
            <th>Expires</th>
            <th>Accepted by</th>
            <th class="shrink"></th>
          </tr>
        </thead>
        <tbody>
          {#each detail.invites as invite (invite.id)}
            <tr>
              <td><StateBadge state={invite.state} /></td>
              <td><RelativeTime value={invite.created_at} /></td>
              <td><RelativeTime value={invite.expires_at} fallback="—" /></td>
              <td>{invite.accepted_by ?? "—"}</td>
              <td class="shrink">
                <div class="cell-actions">
                  {#if invite.state === "open"}
                    <Button
                      variant="danger"
                      size="sm"
                      onclick={() =>
                        askConfirm({
                          action: "?/revokeInvite",
                          title: "Revoke invite?",
                          description: "The link will stop working immediately.",
                          confirmLabel: "Revoke invite",
                          successMessage: "Invite revoked",
                          hidden: { invite_id: invite.id },
                        })}
                    >Revoke</Button>
                  {/if}
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </Table>
    {:else}
      <EmptyState icon="invites" title="No invites" description="Create an invite to bring someone in as this user’s friend." />
    {/if}
  </Section>

  <Section title="Friends" count={detail.counts.friends}>
    {#if detail.friends.length}
      <Table>
        <thead>
          <tr>
            <th>Handle</th>
            <th>Display name</th>
            <th>Friends since</th>
            <th class="shrink"></th>
          </tr>
        </thead>
        <tbody>
          {#each detail.friends as friend (friend.id)}
            <tr>
              <td><a class="row-link" href="/admin/users/{friend.id}">{friend.handle}</a></td>
              <td class="muted">{friend.display_name}</td>
              <td><RelativeTime value={friend.since} dateOnly /></td>
              <td class="shrink">
                <div class="cell-actions">
                  <Button
                    variant="danger"
                    size="sm"
                    onclick={() =>
                      askConfirm({
                        action: "?/removeFriend",
                        title: "Remove friendship?",
                        description: `${user.handle} and ${friend.handle} will no longer see each other. This affects both directions.`,
                        confirmLabel: "Remove",
                        successMessage: "Friendship removed",
                        hidden: { friend_id: friend.id },
                      })}
                  >Remove</Button>
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </Table>
    {:else}
      <EmptyState icon="users" title="No friends" description="Friendships form when someone accepts this user’s invite." />
    {/if}
  </Section>

  <Section title="Danger zone" danger>
    <div class="danger-row">
      <div>
        <p class="danger-title">Delete this user</p>
        <p class="danger-sub">
          Permanently removes {user.handle}, their tokens, statuses, created invites, and
          friendships. Accepted invites they used are kept but unlinked. This cannot be undone.
        </p>
      </div>
      <Button variant="danger" icon="trash" onclick={() => (deleteOpen = true)}>Delete user</Button>
    </div>
  </Section>
</div>

<!-- Mint token modal -->
<Modal bind:open={tokenModalOpen} title="Mint a bearer token" description="The raw token is shown once after creation." size="sm">
  <form method="POST" action="?/mintToken" use:enhance={mintTokenSubmit}>
    <Field name="label" label="label" optional bind:value={tokenLabel} placeholder="MacBook" hint="A note to recognize this token later." />
    <div class="modal-actions">
      <Button variant="ghost" type="button" onclick={() => (tokenModalOpen = false)}>Cancel</Button>
      <Button variant="primary" type="submit" loading={tokenSubmitting}>Mint token</Button>
    </div>
  </form>
</Modal>

<!-- Shared revoke/remove confirmation -->
{#if confirm}
  <ConfirmDialog
    bind:open={confirmOpen}
    action={confirm.action}
    title={confirm.title}
    description={confirm.description}
    confirmLabel={confirm.confirmLabel}
    successMessage={confirm.successMessage}
    danger
  >
    {#snippet fields()}
      {#each Object.entries(confirm.hidden) as [name, value] (name)}
        <input type="hidden" {name} {value} />
      {/each}
    {/snippet}
  </ConfirmDialog>
{/if}

<!-- Delete user (typed confirmation) -->
<ConfirmDialog
  bind:open={deleteOpen}
  action="?/delete"
  title="Delete {user.handle}?"
  description="This permanently deletes the user and all data owned by them."
  confirmLabel="Delete user"
  successMessage="User deleted"
  requireText={user.handle}
  requireLabel="Type the handle to confirm"
  requireHint="Enter “{user.handle}” exactly."
  danger
/>

<style>
  .grid {
    display: flex;
    flex-direction: column;
    gap: var(--space-12);
  }

  .header-status {
    margin-right: var(--space-2);
  }

  .row .since,
  .since {
    color: var(--faint);
    font-size: var(--text-xs);
  }
  .strong {
    color: var(--fg);
  }
  .muted {
    color: var(--muted);
  }

  .id-cell {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
  }

  .sub {
    color: var(--muted);
    font-size: var(--text-xs);
    margin-top: 2px;
  }
  .sub.mono,
  :global(.admin-table td.mono) {
    font-family: var(--font-mono);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-top: var(--space-6);
  }

  .danger-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-6);
    flex-wrap: wrap;
  }
  .danger-title {
    margin: 0;
    font-size: var(--text-sm);
  }
  .danger-sub {
    margin: var(--space-1) 0 0;
    color: var(--muted);
    font-size: var(--text-sm);
    font-weight: var(--weight-light);
    max-width: 48ch;
  }
</style>
