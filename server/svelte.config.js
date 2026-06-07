import adapter from "@sveltejs/adapter-node";
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter(),
    // The app owns its Content-Security-Policy via hashed inline scripts, so
    // the reverse proxy does not need to send a conflicting CSP header.
    csp: {
      mode: "hash",
      directives: {
        "default-src": ["self"],
        "script-src": ["self"],
        "style-src": ["self", "unsafe-inline"],
        "img-src": ["self", "data:"],
        "object-src": ["none"],
        "base-uri": ["none"],
        "frame-ancestors": ["none"],
      },
    },
  },
};

export default config;
