<script>
  /**
   * Thin table chrome. Pages provide <thead>/<tbody> as children; this supplies
   * the house styling: hairline header underline, quiet row separators, a soft
   * hover, and a whole-row link via the `.row-link` helper in the first cell.
   * Horizontal scroll is handled gracefully on narrow viewports.
   */
  let { children } = $props();
</script>

<div class="table-wrap">
  <table class="admin-table">
    {@render children?.()}
  </table>
</div>

<style>
  .table-wrap {
    width: 100%;
    overflow-x: auto;
    /* fade the right edge when content overflows, hinting at scroll */
    margin: 0 calc(-1 * var(--space-1));
  }

  .admin-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--text-sm);
  }

  :global(.admin-table thead th) {
    text-align: left;
    padding: var(--space-2) var(--space-3);
    border-bottom: 1px solid var(--hairline);
    white-space: nowrap;
    font-weight: var(--weight-medium);
    color: var(--muted);
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    text-transform: uppercase;
    vertical-align: bottom;
  }

  :global(.admin-table tbody td) {
    padding: var(--space-3);
    border-bottom: 1px solid var(--hairline);
    vertical-align: middle;
  }

  :global(.admin-table tbody tr) {
    position: relative;
    transition: background 120ms ease;
  }

  :global(.admin-table tbody tr:hover) {
    background: var(--admin-row-hover);
  }

  :global(.admin-table tbody tr:last-child td) {
    border-bottom: none;
  }

  :global(.admin-table .num) {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }

  :global(.admin-table .shrink) {
    width: 1%;
    white-space: nowrap;
  }

  /* Whole-row link: place <a class="row-link"> in a cell; it stretches to cover
     the row while real links/buttons in later cells stay clickable above it. */
  :global(.admin-table .row-link) {
    text-decoration: none;
    color: inherit;
    font-weight: var(--weight-medium);
  }
  :global(.admin-table .row-link::after) {
    content: "";
    position: absolute;
    inset: 0;
  }
  :global(.admin-table tbody tr:focus-within) {
    background: var(--admin-row-hover);
  }
  :global(.admin-table .row-link:focus-visible) {
    outline: none;
  }
  :global(.admin-table .row-link:focus-visible::after) {
    outline: 2px solid var(--admin-focus);
    outline-offset: -2px;
    border-radius: var(--radius-sm);
  }

  /* Interactive cells sit above the stretched row link. */
  :global(.admin-table .cell-actions),
  :global(.admin-table a:not(.row-link)),
  :global(.admin-table button) {
    position: relative;
    z-index: 1;
  }

  :global(.admin-table .cell-actions) {
    display: flex;
    gap: var(--space-1);
    justify-content: flex-end;
  }
</style>
