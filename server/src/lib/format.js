/**
 * Small display helpers shared across the admin pages. Pure formatting — no
 * secrets, no DB access. Times are rendered with a relative phrase plus an
 * absolute title so an operator can hover for the exact moment.
 */

const RELATIVE_STEPS = [
  { limit: 60, div: 1, unit: "second" },
  { limit: 3600, div: 60, unit: "minute" },
  { limit: 86_400, div: 3600, unit: "hour" },
  { limit: 604_800, div: 86_400, unit: "day" },
  { limit: 2_629_800, div: 604_800, unit: "week" },
  { limit: 31_557_600, div: 2_629_800, unit: "month" },
  { limit: Infinity, div: 31_557_600, unit: "year" },
];

/**
 * "3 minutes ago" / "in 2 days" relative to `now` (defaults to current time).
 * Returns "" for nullish input so callers can fall back to an em dash.
 * @param {string | number | Date | null | undefined} value
 * @param {number} [nowMs]
 */
export function relativeTime(value, nowMs = Date.now()) {
  if (value == null) return "";
  const then = value instanceof Date ? value.getTime() : Date.parse(value);
  if (Number.isNaN(then)) return "";
  const deltaSec = (then - nowMs) / 1000;
  const abs = Math.abs(deltaSec);
  if (abs < 5) return "just now";
  const step = RELATIVE_STEPS.find((s) => abs < s.limit) ?? RELATIVE_STEPS.at(-1);
  const amount = Math.round(deltaSec / step.div);
  const count = Math.abs(amount);
  const unit = count === 1 ? step.unit : `${step.unit}s`;
  return amount < 0 ? `${count} ${unit} ago` : `in ${count} ${unit}`;
}

/**
 * Absolute, human timestamp for titles/tooltips, e.g. "Jun 6, 2026, 18:04".
 * @param {string | number | Date | null | undefined} value
 */
export function formatDateTime(value) {
  if (value == null) return "";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
}

/**
 * Date only, e.g. "Jun 6, 2026".
 * @param {string | number | Date | null | undefined} value
 */
export function formatDate(value) {
  if (value == null) return "";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

/** Truncate a long opaque id for display while keeping it copyable elsewhere. */
export function shortId(id, head = 8) {
  const str = String(id ?? "");
  return str.length > head ? `${str.slice(0, head)}…` : str;
}

/** Pluralize a noun against a count: pluralize(1, "device") → "1 device". */
export function pluralize(count, noun, plural = `${noun}s`) {
  return `${count} ${count === 1 ? noun : plural}`;
}
