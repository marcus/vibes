<!-- Neon ribbons + fine density strands backdrop (Option C2), shared by the
     homepage and invite hero sections. Position inside a `position:relative`
     hero with a readability scrim baked in.
     At most one instance per page: the SVG gradient ids (ribA/ribB/ribC) are
     fixed, so two instances would collide. -->
<div class="hero-ribbons" aria-hidden="true">
  <svg viewBox="0 0 1040 420" preserveAspectRatio="xMidYMid slice">
    <defs>
      <linearGradient id="ribA" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stop-color="#a472ff" /><stop offset="50%" stop-color="#ff4d8d" /><stop offset="100%" stop-color="#ff7a3d" />
      </linearGradient>
      <linearGradient id="ribB" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stop-color="#ff7a3d" /><stop offset="55%" stop-color="#ff4d8d" /><stop offset="100%" stop-color="#45d4ff" />
      </linearGradient>
      <linearGradient id="ribC" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stop-color="#6f8cff" /><stop offset="50%" stop-color="#45d4ff" /><stop offset="100%" stop-color="#a472ff" />
      </linearGradient>
    </defs>
    <g class="rib-blur" fill="none" stroke-linecap="round">
      <path d="M-40 150 C 220 40, 360 280, 620 150 S 980 90, 1120 200" stroke="url(#ribA)" stroke-width="10" />
      <path d="M-40 260 C 240 360, 420 120, 640 250 S 1000 320, 1120 210" stroke="url(#ribB)" stroke-width="14" />
      <path d="M-40 90 C 300 180, 520 -20, 760 110 S 1040 40, 1120 120" stroke="url(#ribC)" stroke-width="8" />
    </g>
    <g class="rib-thin-soft" fill="none" stroke-linecap="round" stroke-width="1.5">
      <path d="M-40 130 C 240 80, 440 210, 680 130 S 1010 70, 1120 150" stroke="url(#ribA)" />
      <path d="M-40 290 C 200 240, 420 350, 660 285 S 990 350, 1120 295" stroke="url(#ribB)" />
    </g>
    <g class="rib-thin" fill="none" stroke-linecap="round" stroke-width="1">
      <path d="M-40 110 C 220 60, 420 190, 660 110 S 1000 55, 1120 130" stroke="url(#ribA)" />
      <path d="M-40 175 C 240 140, 460 245, 700 180 S 1010 135, 1120 195" stroke="url(#ribC)" />
      <path d="M-40 235 C 180 285, 400 170, 640 235 S 980 285, 1120 225" stroke="url(#ribB)" />
      <path d="M-40 300 C 220 255, 440 360, 680 300 S 1000 355, 1120 295" stroke="url(#ribC)" />
      <path d="M-40 70 C 260 120, 500 30, 740 95 S 1030 40, 1120 80" stroke="url(#ribA)" />
      <path d="M-40 340 C 200 305, 420 395, 680 340 S 1000 385, 1120 335" stroke="url(#ribB)" />
      <path d="M-40 205 C 300 165, 520 265, 760 205 S 1040 160, 1120 215" stroke="url(#ribC)" />
    </g>
    <g class="rib-sharp" fill="none" stroke-linecap="round">
      <path d="M-40 150 C 220 40, 360 280, 620 150 S 980 90, 1120 200" stroke="url(#ribA)" stroke-width="2" />
      <path d="M-40 260 C 240 360, 420 120, 640 250 S 1000 320, 1120 210" stroke="url(#ribB)" stroke-width="2.5" />
    </g>
  </svg>
</div>

<style>
  .hero-ribbons {
    position: absolute; inset: -8% -12% auto -12%; height: 132%;
    z-index: -1; pointer-events: none;
  }
  .hero-ribbons svg { position: absolute; inset: 0; width: 100%; height: 100%; }
  /* readability scrim — a stronger feathered core right behind the copy,
     plus an outer fade that blends ribbons into the page base (both themes) */
  .hero-ribbons::after {
    content: ""; position: absolute; inset: 0;
    background:
      radial-gradient(ellipse 56% 50% at 50% 40%,
        color-mix(in srgb, var(--bg-base) 80%, transparent) 0%,
        color-mix(in srgb, var(--bg-base) 55%, transparent) 34%,
        transparent 70%),
      radial-gradient(ellipse 62% 60% at 50% 40%, transparent 18%, var(--bg-base) 82%);
  }
  .hero-ribbons .rib-blur { filter: blur(14px) saturate(1.3); opacity: 0.85; }
  .hero-ribbons .rib-sharp { opacity: 0.9; }
  .hero-ribbons .rib-thin { opacity: 0.55; }
  .hero-ribbons .rib-thin-soft { filter: blur(2px); opacity: 0.4; }
  /* neon reads softer on a light canvas */
  :global(html[data-theme="light"]) .hero-ribbons { opacity: 0.62; }
</style>
