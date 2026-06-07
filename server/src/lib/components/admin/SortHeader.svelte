<script>
  import { page } from "$app/stores";
  import Icon from "./Icon.svelte";

  /**
   * A clickable column header that toggles sort direction through the `sort` URL
   * param (`column` / `column:desc`). Renders inside a <th>. Numeric columns
   * align right.
   */
  let { column, label, param = "sort", numeric = false, align = null } = $props();

  let raw = $derived($page.url.searchParams.get(param) ?? "");
  let activeColumn = $derived(raw.split(":")[0]);
  let activeDir = $derived(raw.split(":")[1] === "desc" ? "desc" : "asc");
  let isActive = $derived(activeColumn === column);

  function nextHref() {
    const url = new URL($page.url);
    const nextDir = isActive && activeDir === "asc" ? "desc" : "asc";
    const value = nextDir === "asc" ? column : `${column}:desc`;
    url.searchParams.set(param, value);
    return `${url.pathname}${url.search}`;
  }
</script>

<a
  class="sort"
  class:active={isActive}
  class:numeric={numeric || align === "right"}
  href={nextHref()}
  data-sveltekit-noscroll
  title={isActive ? `Sorted ${activeDir === "asc" ? "ascending" : "descending"}` : `Sort by ${label}`}
>
  <span>{label}</span>
  <span class="indicator" class:visible={isActive}>
    <Icon name={isActive && activeDir === "desc" ? "arrowDown" : "arrowUp"} size={12} />
  </span>
</a>

<style>
  .sort {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    text-decoration: none;
    color: var(--muted);
    font-size: var(--text-xs);
    font-weight: var(--weight-medium);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
    transition: color 120ms ease;
  }

  .sort.numeric {
    flex-direction: row-reverse;
  }

  .sort:hover {
    color: var(--fg);
  }

  .sort.active {
    color: var(--fg);
  }

  .indicator {
    display: inline-flex;
    opacity: 0;
    transition: opacity 120ms ease;
  }
  .sort:hover .indicator {
    opacity: 0.5;
  }
  .indicator.visible {
    opacity: 1;
  }
</style>
