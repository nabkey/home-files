import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  // Root directory for the web app
  root: "web",

  // Base path for GitHub Pages deployment
  base: "/home-files/",

  // Build output directory
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    // Copy the WASM file to the output
    rollupOptions: {
      input: {
        main: resolve(__dirname, "web/index.html"),
      },
    },
  },

  // Development server configuration
  server: {
    port: 3000,
    // Required headers for SharedArrayBuffer support
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

  // Asset handling
  assetsInclude: ["**/*.wasm"],

  // Define globals
  define: {
    __DEV__: JSON.stringify(process.env.NODE_ENV !== "production"),
  },

  // Resolve aliases
  resolve: {
    alias: {
      "@": resolve(__dirname, "web"),
    },
  },
});
