import { defineConfig } from "vite";
import { resolve } from "path";
import pkg from "./package.json";

// Base path configuration:
// - Development: /
// - GitHub Pages: /home-files/zig-shell/
const base = process.env.GITHUB_ACTIONS ? "/home-files/zig-shell/" : "/";

// Version from semantic release tag (CI) or package.json (local dev)
const appVersion = process.env.APP_VERSION || pkg.version;

export default defineConfig({
  // Root directory for the web app
  root: "web",

  // Base path for deployment
  base,

  // Public directory (relative to root)
  publicDir: "public",

  // Build output directory
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, "web/index.html"),
      },
    },
    // Ensure source maps for debugging
    sourcemap: true,
  },

  // Development server configuration
  server: {
    port: 3000,
    // Required headers for SharedArrayBuffer support (local dev)
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },

  // Preview server (for testing production build)
  preview: {
    port: 4173,
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },

  // Worker configuration
  worker: {
    format: "es",
  },

  // Optimize dependencies
  optimizeDeps: {
    exclude: ["@xterm/xterm"],
  },

  // Asset handling - include WASM files
  assetsInclude: ["**/*.wasm"],

  // Define globals
  define: {
    __DEV__: JSON.stringify(process.env.NODE_ENV !== "production"),
    __APP_VERSION__: JSON.stringify(appVersion),
  },

  // Resolve aliases
  resolve: {
    alias: {
      "@": resolve(__dirname, "web"),
    },
  },
});
