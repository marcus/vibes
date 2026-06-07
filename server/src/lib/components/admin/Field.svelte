<script>
  /**
   * Labeled form control: input, textarea, or select. Carries an optional hint
   * and inline error. Styling matches the public invite page fields (flat warm
   * field-bg, accent focus ring) so the whole product feels like one surface.
   */
  let {
    label = null,
    name,
    id = name,
    type = "text",
    as = "input", // input | textarea | select
    value = $bindable(""),
    placeholder = null,
    hint = null,
    error = null,
    required = false,
    optional = false,
    autofocus = false,
    autocomplete = "off",
    rows = 4,
    mono = false,
    oninput = null,
    children, // <option> markup for selects
  } = $props();

  // Controlled value rather than bind:value so a dynamic `type` is allowed on
  // <input> (Svelte forbids bind:value with a dynamic type). Parent two-way
  // binding still works because `value` is $bindable and we assign it here.
  function handleInput(event) {
    value = event.currentTarget.value;
    oninput?.(event);
  }
</script>

<div class="field" class:has-error={error}>
  {#if label}
    <label class="field-label" for={id}>
      {label}
      {#if optional}<span class="optional">optional</span>{/if}
    </label>
  {/if}

  {#if as === "textarea"}
    <textarea
      {id}
      {name}
      {placeholder}
      {required}
      {rows}
      class:mono
      {value}
      oninput={handleInput}
    ></textarea>
  {:else if as === "select"}
    <div class="select-wrap">
      <select {id} {name} {required} {value} oninput={handleInput}>
        {@render children?.()}
      </select>
      <svg class="caret" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg>
    </div>
  {:else}
    <input
      {id}
      {name}
      {type}
      {placeholder}
      {required}
      {autocomplete}
      class:mono
      autocapitalize="off"
      spellcheck="false"
      {value}
      oninput={handleInput}
      {...autofocus ? { autofocus: true } : {}}
    />
  {/if}

  {#if error}
    <p class="msg error">{error}</p>
  {:else if hint}
    <p class="msg hint">{hint}</p>
  {/if}
</div>

<style>
  .field {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .field-label {
    font-size: var(--text-sm);
    color: var(--muted);
    letter-spacing: var(--tracking-wide);
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
  }

  .optional {
    color: var(--faint);
    font-size: var(--text-xs);
  }

  input,
  textarea,
  select {
    width: 100%;
    background: var(--field-bg);
    border: none;
    border-radius: var(--radius-md);
    color: var(--fg);
    font-family: inherit;
    font-size: var(--text-base);
    padding: var(--space-3);
    transition: outline-color 100ms ease, background 120ms ease;
  }

  textarea {
    resize: vertical;
    line-height: var(--leading-normal);
  }

  .mono {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
  }

  input:focus,
  textarea:focus,
  select:focus {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }

  .has-error input,
  .has-error textarea,
  .has-error select {
    outline: 2px solid var(--admin-danger);
    outline-offset: 1px;
  }

  .select-wrap {
    position: relative;
    display: flex;
  }

  select {
    appearance: none;
    padding-right: var(--space-8);
    cursor: pointer;
  }

  .caret {
    position: absolute;
    right: var(--space-3);
    top: 50%;
    transform: translateY(-50%);
    color: var(--muted);
    pointer-events: none;
  }

  .msg {
    margin: 0;
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
  }
  .msg.hint {
    color: var(--faint);
  }
  .msg.error {
    color: var(--admin-danger);
  }
</style>
