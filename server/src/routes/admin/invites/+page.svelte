<script>
  import { enhance } from "$app/forms";
  import { invalidateAll } from "$app/navigation";
  import {
    PageHeader,
    Button,
    Table,
    StateBadge,
    FilterPills,
    EmptyState,
    RelativeTime,
    Modal,
    Field,
    ConfirmDialog,
    SecretReveal,
    pushToast,
  } from "$lib/components/admin/index.js";
  import { pluralize } from "$lib/format.js";

  let { data } = $props();
  let { invites, counts, creators } = $derived(data);

  let revealSecret = $state(null);
  let createOpen = $state(false);
  let creatorId = $state("");
  let creating = $state(false);

  let revokeOpen = $state(false);
  let revokeId = $state(null);

  let filterOptions = $derived([
    { value: "all", label: "All", count: counts.all },
    { value: "open", label: "Open", count: counts.open },
    { value: "accepted", label: "Accepted", count: counts.accepted },
    { value: "expired", label: "Expired", count: counts.expired },
    { value: "revoked", label: "Revoked", count: counts.revoked },
  ]);

  function createSubmit() {
    creating = true;
    return async ({ result }) => {
      creating = false;
      if (result.type === "success" && result.data?.secret) {
        revealSecret = result.data.secret;
        createOpen = false;
        creatorId = "";
        pushToast("Invite created", { tone: "success" });
        await invalidateAll();
      } else if (result.type === "failure") {
        pushToast(result.data?.error ?? "Could not create invite.", { tone: "error" });
      }
    };
  }

  function askRevoke(id) {
    revokeId = id;
    revokeOpen = true;
  }
</script>

<svelte:head><title>Invites · vibes admin</title></svelte:head>

<PageHeader
  eyebrow="invites"
  title="Invites"
  description="Every invite across the relay. Filter by state, create a fresh link for any user, or revoke an open one."
>
  {#snippet actions()}
    <Button variant="primary" icon="plus" onclick={() => (createOpen = true)}>Create invite</Button>
  {/snippet}
</PageHeader>

{#if revealSecret}
  <SecretReveal
    kind="link"
    title="Invite link"
    value={revealSecret.value}
    hint="Send this to the new user. It works once and is shown only here."
    ondismiss={() => (revealSecret = null)}
  />
{/if}

<div class="toolbar">
  <FilterPills param="state" options={filterOptions} />
  <span class="count">{pluralize(invites.length, "invite")}</span>
</div>

{#if invites.length}
  <Table>
    <thead>
      <tr>
        <th>State</th>
        <th>Creator</th>
        <th>Accepted by</th>
        <th>Created</th>
        <th>Expires</th>
        <th class="shrink"></th>
      </tr>
    </thead>
    <tbody>
      {#each invites as invite (invite.id)}
        <tr>
          <td><StateBadge state={invite.state} /></td>
          <td><a class="handle" href="/admin/users/{invite.creator_user_id}">{invite.creator_handle}</a></td>
          <td>{invite.accepted_by ?? "—"}</td>
          <td><RelativeTime value={invite.created_at} /></td>
          <td><RelativeTime value={invite.expires_at} fallback="—" /></td>
          <td class="shrink">
            <div class="cell-actions">
              {#if invite.state === "open"}
                <Button variant="danger" size="sm" onclick={() => askRevoke(invite.id)}>Revoke</Button>
              {/if}
            </div>
          </td>
        </tr>
      {/each}
    </tbody>
  </Table>
{:else}
  <EmptyState
    icon="invites"
    title={data.state === "all" ? "No invites yet" : `No ${data.state} invites`}
    description={data.state === "all" ? "Create an invite to bring someone onto the relay." : "Try a different filter."}
  >
    {#snippet actions()}
      {#if data.state === "all"}
        <Button variant="primary" icon="plus" onclick={() => (createOpen = true)}>Create invite</Button>
      {/if}
    {/snippet}
  </EmptyState>
{/if}

<!-- Create invite modal -->
<Modal bind:open={createOpen} title="Create an invite" description="The one-time link is shown once after creation." size="sm">
  {#if creators.length}
    <form method="POST" action="?/create" use:enhance={createSubmit}>
      <Field as="select" name="creator_id" label="creator" bind:value={creatorId} required>
        <option value="" disabled selected>Choose a user…</option>
        {#each creators as creator (creator.id)}
          <option value={creator.id}>{creator.handle} · {creator.display_name}</option>
        {/each}
      </Field>
      <p class="note">The new user joins as this person’s friend when they accept.</p>
      <div class="modal-actions">
        <Button variant="ghost" type="button" onclick={() => (createOpen = false)}>Cancel</Button>
        <Button variant="primary" type="submit" loading={creating} disabled={!creatorId}>Create invite</Button>
      </div>
    </form>
  {:else}
    <EmptyState icon="users" title="No users yet" description="Create a user first, then mint their invite.">
      {#snippet actions()}
        <Button href="/admin/users/new" variant="primary" icon="plus">New user</Button>
      {/snippet}
    </EmptyState>
  {/if}
</Modal>

<!-- Revoke confirmation -->
<ConfirmDialog
  bind:open={revokeOpen}
  action="?/revoke"
  title="Revoke invite?"
  description="The link will stop working immediately. This cannot be undone."
  confirmLabel="Revoke invite"
  successMessage="Invite revoked"
  danger
>
  {#snippet fields()}
    <input type="hidden" name="invite_id" value={revokeId} />
  {/snippet}
</ConfirmDialog>

<style>
  .toolbar {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    margin-bottom: var(--space-6);
    flex-wrap: wrap;
  }
  .count {
    color: var(--faint);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
  }

  .handle {
    color: var(--fg);
    text-decoration: none;
  }
  .handle:hover {
    color: var(--accent);
  }

  .note {
    margin: var(--space-3) 0 0;
    color: var(--muted);
    font-size: var(--text-xs);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-top: var(--space-6);
  }
</style>
