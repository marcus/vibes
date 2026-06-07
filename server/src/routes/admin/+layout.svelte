<script>
  import "$lib/styles/admin.css";
  import { page } from "$app/stores";
  import { AdminShell } from "$lib/components/admin/index.js";

  let { data, children } = $props();

  // The login page renders standalone (no nav rail); every authenticated page
  // gets the full shell. data.session is null only on the login route.
  let chromeless = $derived($page.url.pathname === "/admin/login");
</script>

{#if chromeless || !data.session}
  {@render children()}
{:else}
  <AdminShell session={data.session}>
    {@render children()}
  </AdminShell>
{/if}
