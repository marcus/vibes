<script>
  import { enhance } from "$app/forms";
  import { invalidateAll } from "$app/navigation";
  import Modal from "./Modal.svelte";
  import Button from "./Button.svelte";
  import Field from "./Field.svelte";
  import { pushToast } from "./toasts.svelte.js";

  /**
   * A confirmation modal backed by a SvelteKit form action. Optionally gated by
   * a typed confirmation (e.g. retype the handle to delete). Handles the enhance
   * lifecycle: loading state, success toast + refresh, and inline error.
   */
  let {
    open = $bindable(false),
    title,
    description = null,
    action,
    confirmLabel = "Confirm",
    cancelLabel = "Cancel",
    danger = false,
    requireText = null,
    requireLabel = "Type to confirm",
    requireHint = null,
    successMessage = "Done",
    fields, // snippet of hidden inputs
    body, // optional extra body snippet above the gate
  } = $props();

  let typed = $state("");
  let submitting = $state(false);
  let error = $state(null);

  let gateMet = $derived(!requireText || typed === requireText);

  $effect(() => {
    if (!open) {
      typed = "";
      error = null;
      submitting = false;
    }
  });

  function submit() {
    submitting = true;
    error = null;
    return async ({ result, update }) => {
      submitting = false;
      if (result.type === "success") {
        open = false;
        pushToast(successMessage, { tone: "success" });
        await invalidateAll();
      } else if (result.type === "failure") {
        error = result.data?.error ?? "Something went wrong.";
      } else {
        await update();
      }
    };
  }
</script>

<Modal bind:open {title} {description} size="sm">
  <form method="POST" {action} use:enhance={submit}>
    {@render fields?.()}
    {#if body}<div class="confirm-body">{@render body()}</div>{/if}

    {#if requireText}
      <Field
        name="confirm_text"
        label={requireLabel}
        hint={requireHint}
        bind:value={typed}
        autocomplete="off"
        mono
      />
    {/if}

    {#if error}<p class="error">{error}</p>{/if}

    <div class="actions">
      <Button variant="ghost" type="button" onclick={() => (open = false)}>{cancelLabel}</Button>
      <Button
        type="submit"
        variant="primary"
        class={danger ? "is-danger" : ""}
        loading={submitting}
        disabled={!gateMet}
      >
        {confirmLabel}
      </Button>
    </div>
  </form>
</Modal>

<style>
  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .error {
    margin: 0;
    color: var(--admin-danger);
    font-size: var(--text-sm);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-top: var(--space-2);
  }

  /* Destructive confirm: tint the accent-filled primary toward danger. They are
     the same hue in this palette, but this keeps intent explicit. */
  :global(.btn.is-danger) {
    background: var(--admin-danger);
  }
</style>
