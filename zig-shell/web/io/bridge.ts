/**
 * I/O Bridge for SharedArrayBuffer Management
 *
 * This module coordinates communication between the main thread and the
 * Web Worker running the WASI kernel. It manages the shared memory buffers
 * for stdin/stdout and handles message passing for non-stream communication.
 */

import {
  RingBufferWriter,
  RingBufferReader,
  createSharedBuffer,
} from "./ringbuffer.js";

/**
 * Message types for worker communication
 */
export type WorkerMessage =
  | { type: "init"; stdinBuffer: SharedArrayBuffer; kernelUrl: string }
  | { type: "stdout"; data: string }
  | { type: "stderr"; data: string }
  | { type: "ready" }
  | { type: "exit"; code: number }
  | { type: "error"; message: string };

/**
 * Main thread bridge for communicating with the kernel worker
 */
export class KernelBridge {
  private worker: Worker | null = null;
  private stdinBuffer: SharedArrayBuffer;
  private stdinWriter: RingBufferWriter;
  private onStdout: (data: string) => void;
  private onStderr: (data: string) => void;
  private onReady: () => void;
  private onExit: (code: number) => void;
  private onError: (message: string) => void;

  constructor(options: {
    onStdout?: (data: string) => void;
    onStderr?: (data: string) => void;
    onReady?: () => void;
    onExit?: (code: number) => void;
    onError?: (message: string) => void;
  }) {
    // Create shared buffer for stdin
    this.stdinBuffer = createSharedBuffer();
    this.stdinWriter = new RingBufferWriter(this.stdinBuffer);

    // Set up callbacks
    this.onStdout = options.onStdout || console.log;
    this.onStderr = options.onStderr || console.error;
    this.onReady = options.onReady || (() => {});
    this.onExit = options.onExit || (() => {});
    this.onError = options.onError || console.error;
  }

  /**
   * Start the kernel worker
   */
  async start(kernelUrl: string): Promise<void> {
    // Create the worker
    this.worker = new Worker(new URL("../worker.ts", import.meta.url), {
      type: "module",
    });

    // Set up message handler
    this.worker.onmessage = (event: MessageEvent<WorkerMessage>) => {
      this.handleMessage(event.data);
    };

    // Handle worker errors
    this.worker.onerror = (error) => {
      this.onError(`Worker error: ${error.message}`);
    };

    // Send initialization message
    this.worker.postMessage({
      type: "init",
      stdinBuffer: this.stdinBuffer,
      kernelUrl: kernelUrl,
    } satisfies WorkerMessage);
  }

  /**
   * Handle messages from the worker
   */
  private handleMessage(message: WorkerMessage): void {
    switch (message.type) {
      case "stdout":
        this.onStdout(message.data);
        break;
      case "stderr":
        this.onStderr(message.data);
        break;
      case "ready":
        this.onReady();
        break;
      case "exit":
        this.onExit(message.code);
        break;
      case "error":
        this.onError(message.message);
        break;
    }
  }

  /**
   * Write data to stdin
   */
  write(data: string): void {
    this.stdinWriter.write(data);
  }

  /**
   * Write raw bytes to stdin
   */
  writeBytes(data: Uint8Array): void {
    this.stdinWriter.writeBytes(data);
  }

  /**
   * Terminate the worker
   */
  terminate(): void {
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
  }

  /**
   * Check if the worker is running
   */
  isRunning(): boolean {
    return this.worker !== null;
  }
}

/**
 * Check if SharedArrayBuffer is available
 * This requires the page to be served with proper COOP/COEP headers
 */
export function isSharedArrayBufferAvailable(): boolean {
  try {
    new SharedArrayBuffer(1);
    return true;
  } catch {
    return false;
  }
}

/**
 * Get the required headers for SharedArrayBuffer support
 */
export function getRequiredHeaders(): Record<string, string> {
  return {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
  };
}
