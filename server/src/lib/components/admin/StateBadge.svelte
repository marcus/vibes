<script module>
  // Map a state string to a visual tone + label. The accent is reserved for
  // genuinely "live" or actionable states (an online friend, an open invite,
  // an active token); everything terminal reads in neutral grays.
  const TONES = {
    online: { tone: "live", label: "online" },
    offline: { tone: "faint", label: "offline" },
    open: { tone: "accent", label: "open" },
    accepted: { tone: "neutral", label: "accepted" },
    expired: { tone: "faint", label: "expired" },
    revoked: { tone: "faint", label: "revoked" },
    active: { tone: "accent", label: "active" },
    disabled: { tone: "faint", label: "disabled" },
    enabled: { tone: "neutral", label: "enabled" },
  };
</script>

<script>
  let { state, label = null, hollow = false } = $props();
  let meta = $derived(TONES[state] ?? { tone: "neutral", label: state });
</script>

<span class="badge {meta.tone}" class:hollow={hollow || state === "revoked"}>
  <span class="dot" class:pulse={meta.tone === "live"}></span>
  <span class="text">{label ?? meta.label}</span>
</span>

<style>
  .badge {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-xs);
    letter-spacing: var(--tracking-wide);
    color: var(--muted);
    white-space: nowrap;
  }

  .dot {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    flex: none;
    background: var(--admin-idle);
  }

  .live .dot,
  .accent .dot {
    background: var(--admin-live);
  }
  .live .text,
  .accent .text {
    color: var(--fg);
  }

  .neutral .dot {
    background: var(--admin-quiet);
  }

  .faint .dot {
    background: var(--admin-idle);
  }

  .hollow .dot {
    background: transparent;
    box-shadow: inset 0 0 0 1.5px var(--admin-idle);
  }

  .pulse {
    position: relative;
  }
  .pulse::after {
    content: "";
    position: absolute;
    inset: -3px;
    border-radius: 50%;
    background: var(--admin-live);
    opacity: 0.5;
    animation: pulse 1.8s ease-out infinite;
  }

  @keyframes pulse {
    0% {
      transform: scale(0.6);
      opacity: 0.5;
    }
    70% {
      transform: scale(2.1);
      opacity: 0;
    }
    100% {
      opacity: 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .pulse::after {
      animation: none;
    }
  }
</style>
