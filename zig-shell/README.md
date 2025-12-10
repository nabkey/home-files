# ZigShell - Browser-based WASI Shell

A browser-based shell environment powered by Zig and WebAssembly. This project implements a POSIX-like shell that runs entirely in the browser, with an in-memory Virtual Filesystem (VFS) and standard shell commands.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Main Thread (UI)                        │
│  ┌─────────────────┐  ┌──────────────────────────────────┐ │
│  │   xterm.js      │  │     KernelBridge                 │ │
│  │   Terminal      │◄─┤  (SharedArrayBuffer Writer)      │ │
│  └─────────────────┘  └──────────────────────────────────┘ │
│           ▲                         │                       │
│           │                         │ postMessage           │
│           │ stdout/stderr           ▼                       │
│  ┌────────┴─────────────────────────────────────────────┐  │
│  │              Web Worker (Kernel Thread)               │  │
│  │  ┌─────────────────────────────────────────────────┐ │  │
│  │  │            WASI Host (JavaScript)               │ │  │
│  │  │  ┌─────────────────────────────────────────┐    │ │  │
│  │  │  │     Zig WASI Kernel (WebAssembly)       │    │ │  │
│  │  │  │  ┌───────────┐  ┌───────────────────┐   │    │ │  │
│  │  │  │  │   Shell   │  │   Virtual FS      │   │    │ │  │
│  │  │  │  │   REPL    │◄─┤  (In-Memory VFS)  │   │    │ │  │
│  │  │  │  └───────────┘  └───────────────────┘   │    │ │  │
│  │  │  └─────────────────────────────────────────┘    │ │  │
│  │  └─────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Features

### Phase 1 (Current)
- **In-Memory VFS**: Unix-style virtual filesystem with directories and files
- **Shell Commands**: `ls`, `cd`, `pwd`, `cat`, `echo`, `mkdir`, `touch`, `clear`, `help`
- **ANSI Colors**: Full color support in the terminal
- **SharedArrayBuffer I/O**: Efficient thread communication for blocking I/O

### Planned (Phase 2+)
- Persistent storage via IndexedDB
- Pipes and redirects
- Environment variables
- Tab completion
- Command history

## Development

### Prerequisites

- **Zig 0.13.0+**: For compiling the WASI kernel
- **Node.js 20+**: For the web development server
- **Modern browser**: Chrome 100+, Firefox 100+, or Safari 16+

### Building

```bash
# Install Node dependencies
npm install

# Build the Zig WASI kernel
npm run build:wasm

# Copy the kernel to the web public directory
cp zig-out/bin/kernel.wasm web/public/

# Start the development server
npm run dev
```

### Project Structure

```
zig-shell/
├── src/
│   ├── kernel/
│   │   ├── main.zig        # Kernel entry point
│   │   ├── shell.zig       # REPL implementation
│   │   └── commands.zig    # Built-in commands
│   ├── vfs/
│   │   ├── root.zig        # VFS public API
│   │   ├── inode.zig       # Inode data structures
│   │   └── fs.zig          # Filesystem operations
│   └── utils/
│       └── tokenizer.zig   # Command line parsing
├── web/
│   ├── index.html          # HTML entry point
│   ├── main.ts             # Main thread entry
│   ├── worker.ts           # Worker thread entry
│   └── io/
│       ├── bridge.ts       # Thread bridge
│       └── ringbuffer.ts   # I/O ring buffer
├── build.zig               # Zig build configuration
├── package.json            # NPM dependencies
├── tsconfig.json           # TypeScript config
└── vite.config.ts          # Vite bundler config
```

## Available Commands

| Command | Description |
|---------|-------------|
| `ls [path]` | List directory contents |
| `cd [path]` | Change current directory |
| `pwd` | Print working directory |
| `cat <file>...` | Display file contents |
| `echo [text]...` | Print text to stdout |
| `mkdir [-p] <dir>...` | Create directories |
| `touch <file>...` | Create empty files |
| `write <file> <content>` | Write content to file |
| `clear` | Clear the terminal |
| `help [cmd]` | Show help information |
| `exit [code]` | Exit the shell |

## Technical Notes

### SharedArrayBuffer Requirements

This application requires `SharedArrayBuffer` for efficient I/O between the main thread and worker. The server must send these headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

### Memory Model

- Initial WASM memory: 2MB (32 pages)
- Maximum WASM memory: 16MB (256 pages)
- VFS uses contiguous `ArrayList` storage (Phase 1)

## License

MIT
