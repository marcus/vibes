<script module>
  // Minimal line-glyph set. Stroke-based, inherits currentColor, no fills, no
  // emoji — in keeping with the spare house style. Each entry is the inner
  // markup of a 24×24 viewBox.
  export const ICONS = {
    overview:
      '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    users:
      '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19.5a5.5 5.5 0 0 1 11 0"/><path d="M16 5.2a3.2 3.2 0 0 1 0 5.6"/><path d="M17.5 14.4a5.5 5.5 0 0 1 3 5.1"/>',
    invites:
      '<path d="M3 8.5 12 14l9-5.5"/><rect x="3" y="5" width="18" height="14" rx="2"/>',
    user: '<circle cx="12" cy="8" r="3.6"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    check: '<path d="m4.5 12.5 5 5 10-11"/>',
    copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    trash:
      '<path d="M4 7h16"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/>',
    power: '<path d="M12 4v8"/><path d="M7 7a7 7 0 1 0 10 0"/>',
    key: '<circle cx="8" cy="14" r="4"/><path d="m11 11 9-9"/><path d="m17 5 2 2"/><path d="m14 8 2 2"/>',
    link: '<path d="M9 15 15 9"/><path d="M11 6.5 13 4.5a4 4 0 0 1 6 6l-2 2"/><path d="M13 17.5 11 19.5a4 4 0 0 1-6-6l2-2"/>',
    logout: '<path d="M14 4h4a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-4"/><path d="M9 12h11"/><path d="m16 8 4 4-4 4"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>',
    arrowUp: '<path d="m6 14 6-6 6 6"/>',
    arrowDown: '<path d="m6 10 6 6 6-6"/>',
    back: '<path d="M20 12H4"/><path d="m10 6-6 6 6 6"/>',
    device: '<rect x="4" y="4" width="16" height="11" rx="1.5"/><path d="M9 20h6"/><path d="M12 15v5"/>',
    clock: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4.5l3 2"/>',
    shield: '<path d="M12 3 5 6v5c0 4.4 3 7.6 7 9 4-1.4 7-4.6 7-9V6z"/>',
    dot: '<circle cx="12" cy="12" r="4"/>',
  };
</script>

<script>
  let { name, size = 16, stroke = 1.6, label = null, class: klass = "" } = $props();
</script>

<svg
  class="icon {klass}"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width={stroke}
  stroke-linecap="round"
  stroke-linejoin="round"
  role={label ? "img" : "presentation"}
  aria-label={label}
  aria-hidden={label ? null : "true"}
>
  {@html ICONS[name] ?? ICONS.dot}
</svg>

<style>
  .icon {
    display: inline-block;
    flex: none;
    vertical-align: -0.15em;
  }
</style>
