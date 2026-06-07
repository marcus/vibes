<script>
  import {
    PageHeader,
    Button,
    Table,
    SortHeader,
    SearchInput,
    StateBadge,
    EmptyState,
    RelativeTime,
  } from "$lib/components/admin/index.js";
  import { pluralize } from "$lib/format.js";

  let { data } = $props();
  let { users, search } = $derived(data);
</script>

<svelte:head><title>Users · vibes admin</title></svelte:head>

<PageHeader
  eyebrow="users"
  title="Users"
  description="Everyone on the relay. Search by handle or name, sort any column, open a row to manage."
>
  {#snippet actions()}
    <Button href="/admin/users/new" variant="primary" icon="plus">New user</Button>
  {/snippet}
</PageHeader>

<div class="toolbar">
  <SearchInput value={search} placeholder="Search users" />
  <span class="count">{pluralize(users.length, "user")}</span>
</div>

{#if users.length}
  <Table>
    <thead>
      <tr>
        <th><SortHeader column="handle" label="Handle" /></th>
        <th><SortHeader column="presence" label="Presence" /></th>
        <th class="num"><SortHeader column="devices" label="Devices" numeric /></th>
        <th class="num"><SortHeader column="tokens" label="Tokens" numeric /></th>
        <th class="num"><SortHeader column="friends" label="Friends" numeric /></th>
        <th><SortHeader column="created_at" label="Joined" /></th>
        <th class="shrink"></th>
      </tr>
    </thead>
    <tbody>
      {#each users as user (user.id)}
        <tr>
          <td>
            <a class="row-link" href="/admin/users/{user.id}">{user.handle}</a>
            <div class="sub">
              {user.display_name}{#if user.disabled}<span class="disabled-tag">disabled</span>{/if}
            </div>
          </td>
          <td><StateBadge state={user.disabled ? "disabled" : user.presence} /></td>
          <td class="num">{user.device_count}</td>
          <td class="num">{user.token_count}</td>
          <td class="num">{user.friend_count}</td>
          <td><RelativeTime value={user.created_at} dateOnly /></td>
          <td class="shrink">
            <div class="cell-actions">
              <Button href="/admin/users/{user.id}" variant="ghost" size="sm" iconRight="chevron">Manage</Button>
            </div>
          </td>
        </tr>
      {/each}
    </tbody>
  </Table>
{:else if search}
  <EmptyState icon="search" title="No users match “{search}”" description="Try a different handle or name." />
{:else}
  <EmptyState icon="users" title="No users yet" description="Create the first user to bootstrap the relay.">
    {#snippet actions()}
      <Button href="/admin/users/new" variant="primary" icon="plus">New user</Button>
    {/snippet}
  </EmptyState>
{/if}

<style>
  .toolbar {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    margin-bottom: var(--space-6);
  }
  .count {
    color: var(--faint);
    font-size: var(--text-sm);
    letter-spacing: var(--tracking-wide);
  }

  .sub {
    color: var(--muted);
    font-size: var(--text-xs);
    margin-top: 2px;
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }
  .disabled-tag {
    color: var(--admin-danger);
    text-transform: uppercase;
    letter-spacing: var(--tracking-wide);
    font-size: 0.625rem;
  }
</style>
