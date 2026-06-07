<script>
  import { enhance } from "$app/forms";
  import { page } from "$app/stores";
  import { Button, Field } from "$lib/components/admin/index.js";

  let { form } = $props();

  let submitting = $state(false);
  let next = $derived($page.url.searchParams.get("next") ?? "/admin");

  function onsubmit() {
    submitting = true;
    return async ({ update }) => {
      await update();
      submitting = false;
    };
  }
</script>

<svelte:head><title>Admin · vibes</title></svelte:head>

<main>
  <div class="card">
    <div class="brand">
      <span class="wordmark">vibes</span>
      <span class="tag">admin</span>
    </div>
    <h1>Sign in.</h1>
    <p class="lede">Enter the admin password to manage the relay.</p>

    {#if form?.error}
      <p class="error" role="alert">{form.error}</p>
    {/if}

    <form method="POST" use:enhance={onsubmit}>
      <input type="hidden" name="next" value={next} />
      <Field
        name="password"
        label="password"
        type="password"
        autocomplete="current-password"
        autofocus
        required
      />
      <Button type="submit" variant="primary" full loading={submitting}>Sign in</Button>
    </form>
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
    max-width: 22rem;
    display: flex;
    flex-direction: column;
  }

  .brand {
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
    margin-bottom: var(--space-8);
  }
  .wordmark {
    font-size: var(--text-lg);
    font-weight: var(--weight-light);
    letter-spacing: var(--tracking-wide);
  }
  .tag {
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
    color: var(--faint);
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
    gap: var(--space-6);
  }

  .error {
    margin: 0 0 var(--space-6);
    color: var(--admin-danger);
    font-size: var(--text-sm);
  }
</style>
