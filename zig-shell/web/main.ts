/**
 * Main Entry Point (Main Thread)
 *
 * This module initializes the terminal UI using xterm.js and connects
 * it to the Zig WASI kernel running in a Web Worker.
 */

import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { KernelBridge, isSharedArrayBufferAvailable } from "./io/bridge.js";

// Import xterm.js CSS
import "@xterm/xterm/css/xterm.css";

// Declare build-time injected global
declare const __APP_VERSION__: string;

/**
 * Terminal configuration
 */
const TERMINAL_OPTIONS = {
  fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
  fontSize: 14,
  lineHeight: 1.2,
  cursorBlink: true,
  cursorStyle: "block" as const,
  theme: {
    background: "#1e1e2e",
    foreground: "#cdd6f4",
    cursor: "#f5e0dc",
    cursorAccent: "#1e1e2e",
    selectionBackground: "#585b70",
    black: "#45475a",
    red: "#f38ba8",
    green: "#a6e3a1",
    yellow: "#f9e2af",
    blue: "#89b4fa",
    magenta: "#f5c2e7",
    cyan: "#94e2d5",
    white: "#bac2de",
    brightBlack: "#585b70",
    brightRed: "#f38ba8",
    brightGreen: "#a6e3a1",
    brightYellow: "#f9e2af",
    brightBlue: "#89b4fa",
    brightMagenta: "#f5c2e7",
    brightCyan: "#94e2d5",
    brightWhite: "#a6adc8",
  },
};

/**
 * Application state
 */
class ShellApp {
  private terminal: Terminal;
  private fitAddon: FitAddon;
  private bridge: KernelBridge | null = null;
  private isReady = false;

  constructor() {
    // Initialize terminal
    this.terminal = new Terminal(TERMINAL_OPTIONS);
    this.fitAddon = new FitAddon();

    // Load addons
    this.terminal.loadAddon(this.fitAddon);

    // Set up event handlers
    this.setupTerminal();
  }

  /**
   * Initialize and start the application
   */
  async start(): Promise<void> {
    const container = document.getElementById("terminal");
    if (!container) {
      throw new Error("Terminal container not found");
    }

    // Open terminal in container
    this.terminal.open(container);
    this.fitAddon.fit();

    // Re-fit after a short delay to handle mobile layout stabilization
    setTimeout(() => this.fitAddon.fit(), 100);

    // Try to load WebGL addon for better performance
    try {
      const webglAddon = new WebglAddon();
      this.terminal.loadAddon(webglAddon);
    } catch (e) {
      console.warn("WebGL addon not available, using canvas renderer");
    }

    // Check for SharedArrayBuffer support
    if (!isSharedArrayBufferAvailable()) {
      this.terminal.writeln(
        "\x1b[1;31mError: SharedArrayBuffer is not available.\x1b[0m"
      );
      this.terminal.writeln("");
      this.terminal.writeln(
        "This application requires SharedArrayBuffer for thread communication."
      );
      this.terminal.writeln("Please ensure the page is served with:");
      this.terminal.writeln("  - Cross-Origin-Opener-Policy: same-origin");
      this.terminal.writeln("  - Cross-Origin-Embedder-Policy: require-corp");
      this.terminal.writeln("");
      this.terminal.writeln(
        "If running locally, use: vite --host with proper headers."
      );
      return;
    }

    // Show loading message
    this.terminal.writeln("\x1b[1;34mZigShell\x1b[0m - Browser-based Shell");
    this.terminal.writeln("Loading kernel...");
    this.terminal.writeln("");

    // Initialize the kernel bridge
    await this.initKernel();
  }

  /**
   * Set up terminal event handlers
   */
  private setupTerminal(): void {
    // Handle terminal input
    this.terminal.onData((data) => {
      if (this.isReady && this.bridge) {
        // Convert Enter key to newline
        const converted = data.replace("\r", "\n");
        this.bridge.write(converted);
      }
    });

    // Handle resize
    window.addEventListener("resize", () => {
      this.fitAddon.fit();
    });

    // Handle mobile viewport changes (keyboard, address bar)
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", () => {
        this.fitAddon.fit();
      });
    }
  }

  /**
   * Initialize the kernel bridge and start the WASI kernel
   */
  private async initKernel(): Promise<void> {
    this.bridge = new KernelBridge({
      onStdout: (data) => {
        // Convert LF to CRLF for terminal
        const converted = data.replace(/\n/g, "\r\n");
        this.terminal.write(converted);
      },
      onStderr: (data) => {
        const converted = data.replace(/\n/g, "\r\n");
        this.terminal.write(`\x1b[31m${converted}\x1b[0m`);
      },
      onReady: () => {
        this.isReady = true;
        this.terminal.writeln("\x1b[1;32mKernel ready.\x1b[0m");
        this.terminal.writeln("");
      },
      onExit: (code) => {
        this.isReady = false;
        this.terminal.writeln("");
        this.terminal.writeln(`\x1b[33mKernel exited with code ${code}\x1b[0m`);
      },
      onError: (message) => {
        this.terminal.writeln(`\x1b[1;31mError: ${message}\x1b[0m`);
      },
    });

    try {
      // Start the kernel with the WASM file path
      // Use Vite's BASE_URL to handle deployment to subdirectories
      const kernelPath = `${import.meta.env.BASE_URL}kernel.wasm`;
      await this.bridge.start(kernelPath);
    } catch (error) {
      this.terminal.writeln(
        `\x1b[1;31mFailed to start kernel: ${error}\x1b[0m`
      );
    }
  }

  /**
   * Clean up resources
   */
  destroy(): void {
    if (this.bridge) {
      this.bridge.terminate();
    }
    this.terminal.dispose();
  }
}

// ============================================================================
// Application Bootstrap
// ============================================================================

// Wait for DOM to be ready
document.addEventListener("DOMContentLoaded", async () => {
  // Inject version into header
  const versionEl = document.getElementById("app-version");
  if (versionEl) {
    versionEl.textContent = `v${__APP_VERSION__}`;
  }

  const app = new ShellApp();

  try {
    await app.start();
  } catch (error) {
    console.error("Failed to start application:", error);
  }

  // Handle cleanup on page unload
  window.addEventListener("beforeunload", () => {
    app.destroy();
  });
});
