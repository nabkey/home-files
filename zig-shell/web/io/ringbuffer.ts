/**
 * Ring Buffer for I/O Synchronization
 *
 * This module implements a circular buffer using SharedArrayBuffer and Atomics
 * for efficient, thread-safe communication between the main thread and Web Worker.
 *
 * Buffer Layout (4KB total):
 * - Header (8 bytes):
 *   - [0-3]: Write Head Index (Atomic u32)
 *   - [4-7]: Read Head Index (Atomic u32)
 * - Body (4088 bytes):
 *   - Circular storage for character bytes
 */

const HEADER_SIZE = 8;
const DEFAULT_BUFFER_SIZE = 4096;

/**
 * Ring Buffer Writer for the main thread
 * Writes data to the shared buffer and notifies the worker
 */
export class RingBufferWriter {
  private header: Int32Array;
  private data: Uint8Array;
  private capacity: number;
  private encoder: TextEncoder;

  constructor(sab: SharedArrayBuffer) {
    this.header = new Int32Array(sab, 0, 2);
    this.data = new Uint8Array(sab, HEADER_SIZE);
    this.capacity = this.data.length;
    this.encoder = new TextEncoder();
  }

  /**
   * Write a string to the ring buffer
   */
  write(chunk: string): number {
    const bytes = this.encoder.encode(chunk);
    return this.writeBytes(bytes);
  }

  /**
   * Write raw bytes to the ring buffer
   */
  writeBytes(bytes: Uint8Array): number {
    let writeIndex = Atomics.load(this.header, 0);
    const readIndex = Atomics.load(this.header, 1);

    // Calculate available space
    const used = (writeIndex - readIndex + this.capacity) % this.capacity;
    const available = this.capacity - used - 1; // Keep one slot empty to distinguish full from empty

    if (bytes.length > available) {
      console.warn(
        `Ring buffer overflow: ${bytes.length} bytes requested, ${available} available`
      );
      // Write as much as we can
      bytes = bytes.subarray(0, available);
    }

    // Write bytes to the circular buffer
    for (let i = 0; i < bytes.length; i++) {
      this.data[writeIndex % this.capacity] = bytes[i];
      writeIndex++;
    }

    // Update write head
    Atomics.store(this.header, 0, writeIndex);

    // Notify any waiting readers
    Atomics.notify(this.header, 0, 1);

    return bytes.length;
  }

  /**
   * Get the number of bytes available for reading
   */
  available(): number {
    const writeIndex = Atomics.load(this.header, 0);
    const readIndex = Atomics.load(this.header, 1);
    return (writeIndex - readIndex + this.capacity) % this.capacity;
  }

  /**
   * Check if the buffer is empty
   */
  isEmpty(): boolean {
    return this.available() === 0;
  }
}

/**
 * Ring Buffer Reader for the worker thread
 * Reads data from the shared buffer, blocking if necessary
 */
export class RingBufferReader {
  private header: Int32Array;
  private data: Uint8Array;
  private capacity: number;
  private decoder: TextDecoder;

  constructor(sab: SharedArrayBuffer) {
    this.header = new Int32Array(sab, 0, 2);
    this.data = new Uint8Array(sab, HEADER_SIZE);
    this.capacity = this.data.length;
    this.decoder = new TextDecoder();
  }

  /**
   * Read bytes from the ring buffer (blocking)
   * This will wait until data is available
   */
  read(buffer: Uint8Array): number {
    let writeIndex = Atomics.load(this.header, 0);
    let readIndex = Atomics.load(this.header, 1);

    // Wait for data if buffer is empty
    while (writeIndex === readIndex) {
      // Wait on the write index to change
      // This halts the Worker thread completely until notified
      Atomics.wait(this.header, 0, writeIndex);

      // Reload indices after waking up
      writeIndex = Atomics.load(this.header, 0);
      readIndex = Atomics.load(this.header, 1);
    }

    // Read available data
    let bytesRead = 0;
    while (readIndex !== writeIndex && bytesRead < buffer.length) {
      buffer[bytesRead] = this.data[readIndex % this.capacity];
      readIndex++;
      bytesRead++;
    }

    // Update read head
    Atomics.store(this.header, 1, readIndex);

    return bytesRead;
  }

  /**
   * Non-blocking read - returns 0 if no data available
   */
  tryRead(buffer: Uint8Array): number {
    const writeIndex = Atomics.load(this.header, 0);
    let readIndex = Atomics.load(this.header, 1);

    if (writeIndex === readIndex) {
      return 0;
    }

    // Read available data
    let bytesRead = 0;
    while (readIndex !== writeIndex && bytesRead < buffer.length) {
      buffer[bytesRead] = this.data[readIndex % this.capacity];
      readIndex++;
      bytesRead++;
    }

    // Update read head
    Atomics.store(this.header, 1, readIndex);

    return bytesRead;
  }

  /**
   * Read a single byte (blocking)
   */
  readByte(): number {
    const buffer = new Uint8Array(1);
    this.read(buffer);
    return buffer[0];
  }

  /**
   * Read until newline (blocking)
   */
  readLine(): string {
    const bytes: number[] = [];

    while (true) {
      const byte = this.readByte();
      if (byte === 0x0a) {
        // LF
        break;
      }
      if (byte === 0x0d) {
        // CR - skip
        continue;
      }
      bytes.push(byte);
    }

    return this.decoder.decode(new Uint8Array(bytes));
  }

  /**
   * Get the number of bytes available for reading
   */
  available(): number {
    const writeIndex = Atomics.load(this.header, 0);
    const readIndex = Atomics.load(this.header, 1);
    return (writeIndex - readIndex + this.capacity) % this.capacity;
  }

  /**
   * Check if data is available (non-blocking)
   */
  hasData(): boolean {
    return this.available() > 0;
  }
}

/**
 * Create a new SharedArrayBuffer for the ring buffer
 */
export function createSharedBuffer(
  size: number = DEFAULT_BUFFER_SIZE
): SharedArrayBuffer {
  return new SharedArrayBuffer(size + HEADER_SIZE);
}
