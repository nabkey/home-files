/**
 * Main Entry Point (Main Thread)
 *
 * This module initializes the terminal UI using ghostty-web and connects
 * it to the Zig WASI kernel running in a Web Worker.
 */

import { Terminal, FitAddon } from "ghostty-web";
import { KernelBridge, isSharedArrayBufferAvailable } from "./io/bridge.js";

// Declare build-time injected global
declare const __APP_VERSION__: string;

/**
 * Terminal configuration (Catppuccin Mocha theme)
 */
const TERMINAL_OPTIONS = {
  fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
  fontSize: 14,
  theme: {
    background: "#1e1e2e",
    foreground: "#cdd6f4",
    cursor: "#f5e0dc",
    selection: "#585b70",
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
  private terminal: Terminal | null = null;
  private fitAddon: FitAddon | null = null;
  private bridge: KernelBridge | null = null;
  private isReady = false;

  constructor() {
    // Terminal is created in start()
  }

  /**
   * Initialize and start the application
   */
  async start(): Promise<void> {
    const container = document.getElementById("terminal");
    if (!container) {
      throw new Error("Terminal container not found");
    }

    // Create terminal and fit addon
    this.terminal = new Terminal(TERMINAL_OPTIONS);
    this.fitAddon = new FitAddon();
    this.terminal.loadAddon(this.fitAddon);

    // Open terminal in container (async - initializes WASM)
    await this.terminal.open(container);
    this.fitAddon.fit();

    // Enable automatic resize observation
    this.fitAddon.observeResize();

    // Set up event handlers
    this.setupTerminal();

    // Check for SharedArrayBuffer support
    if (!isSharedArrayBufferAvailable()) {
      this.terminal.write(
        "\x1b[1;31mError: SharedArrayBuffer is not available.\x1b[0m\r\n"
      );
      this.terminal.write("\r\n");
      this.terminal.write(
        "This application requires SharedArrayBuffer for thread communication.\r\n"
      );
      this.terminal.write("Please ensure the page is served with:\r\n");
      this.terminal.write("  - Cross-Origin-Opener-Policy: same-origin\r\n");
      this.terminal.write("  - Cross-Origin-Embedder-Policy: require-corp\r\n");
      this.terminal.write("\r\n");
      this.terminal.write(
        "If running locally, use: vite --host with proper headers.\r\n"
      );
      return;
    }

    // Show loading message
    this.terminal.write("\x1b[1;34mZigShell\x1b[0m - Browser-based Shell\r\n");
    this.terminal.write("Loading kernel...\r\n");
    this.terminal.write("\r\n");

    // Initialize the kernel bridge
    await this.initKernel();
  }

  /**
   * Set up terminal event handlers
   */
  private setupTerminal(): void {
    if (!this.terminal) return;

    // Handle terminal input - kernel handles echo
    this.terminal.onData((data: string) => {
      if (this.isReady && this.bridge) {
        // Convert Enter key to newline and send to kernel
        // The kernel echoes input back to stdout
        const converted = data.replace("\r", "\n");
        this.bridge.write(converted);
      }
    });
  }

  /**
   * Initialize the kernel bridge and start the WASI kernel
   */
  private async initKernel(): Promise<void> {
    if (!this.terminal) return;

    const terminal = this.terminal;

    this.bridge = new KernelBridge({
      onStdout: (data) => {
        // Convert LF to CRLF for terminal
        const converted = data.replace(/\n/g, "\r\n");
        terminal.write(converted);
      },
      onStderr: (data) => {
        const converted = data.replace(/\n/g, "\r\n");
        terminal.write(`\x1b[31m${converted}\x1b[0m`);
      },
      onReady: () => {
        this.isReady = true;
        terminal.write("\x1b[1;32mKernel ready.\x1b[0m\r\n");
        terminal.write("\r\n");
      },
      onExit: (code) => {
        this.isReady = false;
        terminal.write("\r\n");
        terminal.write(`\x1b[33mKernel exited with code ${code}\x1b[0m\r\n`);
      },
      onError: (message) => {
        terminal.write(`\x1b[1;31mError: ${message}\x1b[0m\r\n`);
      },
    });

    try {
      // Start the kernel with the WASM file path
      // Use Vite's BASE_URL to handle deployment to subdirectories
      const kernelPath = `${import.meta.env.BASE_URL}kernel.wasm`;
      await this.bridge.start(kernelPath);
    } catch (error) {
      terminal.write(`\x1b[1;31mFailed to start kernel: ${error}\x1b[0m\r\n`);
    }
  }

  /**
   * Clean up resources
   */
  destroy(): void {
    if (this.bridge) {
      this.bridge.terminate();
    }
    if (this.fitAddon) {
      this.fitAddon.dispose();
    }
    if (this.terminal) {
      this.terminal.dispose();
    }
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
