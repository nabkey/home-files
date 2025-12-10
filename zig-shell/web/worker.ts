/**
 * WASI Kernel Host (Worker Thread)
 *
 * This Web Worker hosts the Zig WASI kernel, providing the WASI system
 * interface implementation and managing I/O through SharedArrayBuffer.
 */

import { RingBufferReader } from "./io/ringbuffer.js";
import type { WorkerMessage } from "./io/bridge.js";

// WASI imports from the shim library
// Note: The actual import will depend on which WASI shim is available
// We'll implement a minimal shim inline for Phase 1

/**
 * Minimal WASI implementation for the kernel
 */
class WASIHost {
  private memory: WebAssembly.Memory | null = null;
  private stdinReader: RingBufferReader | null = null;
  private decoder = new TextDecoder();
  private encoder = new TextEncoder();

  constructor(stdinBuffer: SharedArrayBuffer) {
    this.stdinReader = new RingBufferReader(stdinBuffer);
  }

  setMemory(memory: WebAssembly.Memory): void {
    this.memory = memory;
  }

  /**
   * Get the WASI imports object
   */
  getImports(): WebAssembly.Imports {
    return {
      wasi_snapshot_preview1: {
        // Process args
        args_get: this.args_get.bind(this),
        args_sizes_get: this.args_sizes_get.bind(this),

        // Environment
        environ_get: this.environ_get.bind(this),
        environ_sizes_get: this.environ_sizes_get.bind(this),

        // Clock
        clock_time_get: this.clock_time_get.bind(this),

        // File descriptors
        fd_read: this.fd_read.bind(this),
        fd_write: this.fd_write.bind(this),
        fd_close: this.fd_close.bind(this),
        fd_seek: this.fd_seek.bind(this),
        fd_fdstat_get: this.fd_fdstat_get.bind(this),
        fd_fdstat_set_flags: this.fd_fdstat_set_flags.bind(this),
        fd_prestat_get: this.fd_prestat_get.bind(this),
        fd_prestat_dir_name: this.fd_prestat_dir_name.bind(this),

        // Path operations (stubs for Phase 1)
        path_open: this.path_open.bind(this),
        path_filestat_get: this.path_filestat_get.bind(this),

        // Process
        proc_exit: this.proc_exit.bind(this),

        // Random
        random_get: this.random_get.bind(this),

        // Poll (stub)
        poll_oneoff: this.poll_oneoff.bind(this),
      },
    };
  }

  // ============================================================================
  // WASI Syscall Implementations
  // ============================================================================

  private args_get(argv: number, argv_buf: number): number {
    // No command line args for now
    return 0; // ESUCCESS
  }

  private args_sizes_get(argc_ptr: number, argv_buf_size_ptr: number): number {
    if (!this.memory) return 8; // EBADF
    const view = new DataView(this.memory.buffer);
    view.setUint32(argc_ptr, 0, true);
    view.setUint32(argv_buf_size_ptr, 0, true);
    return 0; // ESUCCESS
  }

  private environ_get(environ: number, environ_buf: number): number {
    // No environment variables for now
    return 0; // ESUCCESS
  }

  private environ_sizes_get(
    environ_count_ptr: number,
    environ_buf_size_ptr: number
  ): number {
    if (!this.memory) return 8; // EBADF
    const view = new DataView(this.memory.buffer);
    view.setUint32(environ_count_ptr, 0, true);
    view.setUint32(environ_buf_size_ptr, 0, true);
    return 0; // ESUCCESS
  }

  private clock_time_get(
    clock_id: number,
    precision: bigint,
    time_ptr: number
  ): number {
    if (!this.memory) return 8; // EBADF
    const view = new DataView(this.memory.buffer);
    const now = BigInt(Date.now()) * BigInt(1_000_000); // Convert to nanoseconds
    view.setBigUint64(time_ptr, now, true);
    return 0; // ESUCCESS
  }

  private fd_read(
    fd: number,
    iovs_ptr: number,
    iovs_len: number,
    nread_ptr: number
  ): number {
    if (!this.memory) return 8; // EBADF

    const view = new DataView(this.memory.buffer);
    const mem = new Uint8Array(this.memory.buffer);

    // Only handle stdin (fd 0)
    if (fd !== 0) {
      return 8; // EBADF
    }

    if (!this.stdinReader) {
      return 8; // EBADF
    }

    let totalRead = 0;

    // Process each iovec
    for (let i = 0; i < iovs_len; i++) {
      const iovPtr = iovs_ptr + i * 8;
      const bufPtr = view.getUint32(iovPtr, true);
      const bufLen = view.getUint32(iovPtr + 4, true);

      // Read into this buffer
      const buffer = new Uint8Array(bufLen);
      const bytesRead = this.stdinReader.read(buffer);

      // Copy to WASM memory
      mem.set(buffer.subarray(0, bytesRead), bufPtr);
      totalRead += bytesRead;

      // If we got less than requested, stop
      if (bytesRead < bufLen) {
        break;
      }
    }

    view.setUint32(nread_ptr, totalRead, true);
    return 0; // ESUCCESS
  }

  private fd_write(
    fd: number,
    iovs_ptr: number,
    iovs_len: number,
    nwritten_ptr: number
  ): number {
    if (!this.memory) return 8; // EBADF

    const view = new DataView(this.memory.buffer);
    const mem = new Uint8Array(this.memory.buffer);

    // Handle stdout (fd 1) and stderr (fd 2)
    if (fd !== 1 && fd !== 2) {
      return 8; // EBADF
    }

    let totalWritten = 0;
    let output = "";

    // Process each iovec
    for (let i = 0; i < iovs_len; i++) {
      const iovPtr = iovs_ptr + i * 8;
      const bufPtr = view.getUint32(iovPtr, true);
      const bufLen = view.getUint32(iovPtr + 4, true);

      // Read from WASM memory
      const bytes = mem.slice(bufPtr, bufPtr + bufLen);
      output += this.decoder.decode(bytes);
      totalWritten += bufLen;
    }

    // Send to main thread
    const message: WorkerMessage = {
      type: fd === 1 ? "stdout" : "stderr",
      data: output,
    };
    self.postMessage(message);

    view.setUint32(nwritten_ptr, totalWritten, true);
    return 0; // ESUCCESS
  }

  private fd_close(fd: number): number {
    // Don't close standard streams
    if (fd <= 2) {
      return 0; // ESUCCESS
    }
    return 8; // EBADF
  }

  private fd_seek(
    fd: number,
    offset: bigint,
    whence: number,
    newoffset_ptr: number
  ): number {
    // Not implemented for Phase 1
    return 70; // ENOSYS
  }

  private fd_fdstat_get(fd: number, fdstat_ptr: number): number {
    if (!this.memory) return 8; // EBADF
    const view = new DataView(this.memory.buffer);

    // Return basic fdstat for standard streams
    if (fd <= 2) {
      // fs_filetype (u8): FILETYPE_CHARACTER_DEVICE = 2
      view.setUint8(fdstat_ptr, 2);
      // fs_flags (u16)
      view.setUint16(fdstat_ptr + 2, 0, true);
      // fs_rights_base (u64)
      view.setBigUint64(fdstat_ptr + 8, BigInt(0xffffffff), true);
      // fs_rights_inheriting (u64)
      view.setBigUint64(fdstat_ptr + 16, BigInt(0xffffffff), true);
      return 0; // ESUCCESS
    }

    return 8; // EBADF
  }

  private fd_fdstat_set_flags(fd: number, flags: number): number {
    return 0; // ESUCCESS (no-op)
  }

  private fd_prestat_get(fd: number, prestat_ptr: number): number {
    // No preopened directories in Phase 1
    return 8; // EBADF
  }

  private fd_prestat_dir_name(
    fd: number,
    path_ptr: number,
    path_len: number
  ): number {
    return 8; // EBADF
  }

  private path_open(
    dirfd: number,
    dirflags: number,
    path_ptr: number,
    path_len: number,
    oflags: number,
    fs_rights_base: bigint,
    fs_rights_inheriting: bigint,
    fdflags: number,
    fd_ptr: number
  ): number {
    // Not implemented for Phase 1 - using internal VFS
    return 70; // ENOSYS
  }

  private path_filestat_get(
    fd: number,
    flags: number,
    path_ptr: number,
    path_len: number,
    filestat_ptr: number
  ): number {
    // Not implemented for Phase 1
    return 70; // ENOSYS
  }

  private proc_exit(code: number): void {
    const message: WorkerMessage = {
      type: "exit",
      code: code,
    };
    self.postMessage(message);
    // Note: In a real implementation, we'd need to actually stop execution
    throw new Error(`Process exited with code ${code}`);
  }

  private random_get(buf_ptr: number, buf_len: number): number {
    if (!this.memory) return 8; // EBADF
    const mem = new Uint8Array(this.memory.buffer);

    // Fill with random bytes
    const randomBytes = new Uint8Array(buf_len);
    crypto.getRandomValues(randomBytes);
    mem.set(randomBytes, buf_ptr);

    return 0; // ESUCCESS
  }

  private poll_oneoff(
    in_ptr: number,
    out_ptr: number,
    nsubscriptions: number,
    nevents_ptr: number
  ): number {
    // Minimal implementation - just return immediately
    if (!this.memory) return 8; // EBADF
    const view = new DataView(this.memory.buffer);
    view.setUint32(nevents_ptr, 0, true);
    return 0; // ESUCCESS
  }
}

// ============================================================================
// Worker Message Handler
// ============================================================================

let wasiHost: WASIHost | null = null;

self.onmessage = async (event: MessageEvent<WorkerMessage>) => {
  const message = event.data;

  if (message.type === "init") {
    try {
      // Initialize WASI host with stdin buffer
      wasiHost = new WASIHost(message.stdinBuffer);

      // Fetch and compile the WASM module
      const response = await fetch(message.kernelUrl);
      const wasmBytes = await response.arrayBuffer();

      // Instantiate the module
      const module = await WebAssembly.compile(wasmBytes);
      const instance = await WebAssembly.instantiate(
        module,
        wasiHost.getImports()
      );

      // Set up memory access
      const memory = instance.exports.memory as WebAssembly.Memory;
      wasiHost.setMemory(memory);

      // Notify that we're ready
      const readyMessage: WorkerMessage = { type: "ready" };
      self.postMessage(readyMessage);

      // Start the WASI application
      const start = instance.exports._start as () => void;
      start();
    } catch (error) {
      const errorMessage: WorkerMessage = {
        type: "error",
        message: error instanceof Error ? error.message : String(error),
      };
      self.postMessage(errorMessage);
    }
  }
};
