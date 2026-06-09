<script>
  import {
    PageHeader,
    Section,
    Stat,
    StateBadge,
    Button,
    EmptyState,
    RelativeTime,
  } from "$lib/components/admin/index.js";

  let { data } = $props();
  let { stats, online, recentInvites, audit } = $derived(data);

  const AUDIT_LABELS = {
    "user.disable": "disabled a user",
    "user.enable": "enabled a user",
    "user.delete": "deleted a user",
    "invite.create": "created an invite",
    "invite.revoke": "revoked an invite",
    "token.create": "minted a token",
    "token.revoke": "revoked a token",
    "friendship.remove": "removed a friendship",
  };
</script>

<svelte:head><title>Overview · vibes admin</title></svelte:head>

<PageHeader eyebrow="overview" title="Relay at a glance">
  {#snippet actions()}
    <Button href="/admin/users/new" variant="primary" icon="plus">New user</Button>
  {/snippet}
</PageHeader>

<div class="stats">
  <Stat
    label="users"
    value={stats.users.total}
    sub={stats.users.disabled ? `${stats.users.disabled} disabled` : "all active"}
    href="/admin/users"
  />
  <Stat label="active tokens" value={stats.active_tokens} />
  <Stat
    label="invites"
    value={stats.invites.total}
    href="/admin/invites"
    parts={[
      { label: "open", value: stats.invites.open },
      { label: "accepted", value: stats.invites.accepted },
      { label: "expired", value: stats.invites.expired },
      { label: "revoked", value: stats.invites.revoked },
    ]}
  />
  <Stat
    label="presence"
    value={stats.presence.online}
    sub="online now"
    accent={stats.presence.online > 0}
    parts={[
      { label: "offline", value: stats.presence.offline },
    ]}
  />
</div>

<div class="columns">
  <Section title="Online now" count={online.length}>
    {#if online.length}
      <ul class="people">
        {#each online as person (person.id)}
          <li>
            <a class="person" href="/admin/users/{person.id}">
              <span class="who">
                <StateBadge state="online" label={person.handle} />
              </span>
              <span class="name">{person.display_name}</span>
              <span class="when"><RelativeTime value={person.updated_at} /></span>
            </a>
          </li>
        {/each}
      </ul>
    {:else}
      <EmptyState icon="dot" title="No one is online" description="Live presence will show up here as friends start sharing." />
    {/if}
  </Section>

  <Section title="Recent invites" count={recentInvites.length}>
    {#snippet actions()}
      <Button href="/admin/invites" variant="ghost" size="sm">View all</Button>
    {/snippet}
    {#if recentInvites.length}
      <ul class="invites">
        {#each recentInvites as invite (invite.id)}
          <li>
            <span class="state"><StateBadge state={invite.state} /></span>
            <span class="meta">
              from <a href="/admin/users/{invite.creator_user_id}" class="handle">{invite.creator_handle}</a>
              {#if invite.accepted_by}<span class="arrow">→</span> <span class="handle">{invite.accepted_by}</span>{/if}
            </span>
            <span class="when"><RelativeTime value={invite.created_at} /></span>
          </li>
        {/each}
      </ul>
    {:else}
      <EmptyState icon="invites" title="No invites yet" />
    {/if}
  </Section>
</div>

{#if audit.length}
  <Section title="Recent admin activity">
    <ul class="audit">
      {#each audit as entry (entry.id)}
        <li>
          <span class="action">{AUDIT_LABELS[entry.action] ?? entry.action}</span>
          {#if entry.detail}<span class="detail">{entry.detail}</span>{/if}
          <span class="when"><RelativeTime value={entry.created_at} /></span>
        </li>
      {/each}
    </ul>
  </Section>
{/if}

<style>
  .stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
    gap: var(--space-3);
    margin-bottom: var(--space-12);
  }

  .columns {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-12);
    margin-bottom: var(--space-12);
  }
  @media (max-width: 52rem) {
    .columns {
      grid-template-columns: 1fr;
      gap: var(--space-8);
    }
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .people li,
  .invites li,
  .audit li {
    border-bottom: 1px solid var(--hairline);
  }
  .people li:last-child,
  .invites li:last-child,
  .audit li:last-child {
    border-bottom: none;
  }

  .person {
    display: grid;
    grid-template-columns: 1fr auto;
    grid-template-areas: "who when" "name when";
    align-items: center;
    gap: 0 var(--space-3);
    padding: var(--space-3) var(--space-2);
    text-decoration: none;
    color: inherit;
    border-radius: var(--radius-sm);
    transition: background 120ms ease;
  }
  .person:hover {
    background: var(--admin-row-hover);
  }
  .who {
    grid-area: who;
  }
  .name {
    grid-area: name;
    color: var(--muted);
    font-size: var(--text-sm);
  }
  .when {
    grid-area: when;
    color: var(--faint);
    font-size: var(--text-xs);
    text-align: right;
  }

  .invites li {
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-2);
  }
  .invites .meta {
    font-size: var(--text-sm);
    color: var(--muted);
  }
  .handle {
    color: var(--fg);
    text-decoration: none;
  }
  .handle:hover {
    color: var(--accent);
  }
  .arrow {
    color: var(--faint);
  }

  .audit li {
    display: flex;
    align-items: baseline;
    gap: var(--space-3);
    padding: var(--space-2);
    font-size: var(--text-sm);
  }
  .audit .action {
    color: var(--fg);
  }
  .audit .detail {
    color: var(--muted);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
  }
  .audit .when {
    margin-left: auto;
  }
</style>
