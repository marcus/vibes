export async function load({ fetch }) {
  try {
    const response = await fetch("/downloads/latest.json");

    if (!response.ok) {
      return { release: null };
    }

    const manifest = await response.json();
    const version = typeof manifest.version === "string" ? manifest.version.trim() : "";

    return {
      release: version ? { version } : null
    };
  } catch {
    return { release: null };
  }
}
