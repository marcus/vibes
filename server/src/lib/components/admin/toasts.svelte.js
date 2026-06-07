/**
 * Tiny toast store for transient action feedback. Runes-based module state so any
 * component can push a toast and the single <Toaster> renders them.
 */

let nextId = 1;

export const toastStore = $state({ items: [] });

/**
 * @param {string} message
 * @param {{ tone?: 'success' | 'error' | 'info', duration?: number }} [options]
 */
export function pushToast(message, { tone = "info", duration = 4000 } = {}) {
  const id = nextId++;
  toastStore.items.push({ id, message, tone });
  if (duration > 0) {
    setTimeout(() => dismissToast(id), duration);
  }
  return id;
}

export function dismissToast(id) {
  const index = toastStore.items.findIndex((t) => t.id === id);
  if (index !== -1) toastStore.items.splice(index, 1);
}
