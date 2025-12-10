# homestruct

**homestruct** is a standalone, compiled "Home Files Generator" written in Go.

Unlike traditional dotfile managers that rely on symlinks (GNU Stow) or complex functional package managers (Nix), `homestruct` takes a **generator approach**. It compiles your templates into a single binary and renders them onto the host machine, handling OS-specific logic (macOS vs. Linux) at generation time.

## Goals

- **Zero Dependency Deployment:** The only requirement to set up a new machine is this binary.
- **Immutable Source, Mutable Destination:** No symlinks. We generate real files. If you change a local file, it drifts. Re-run `homestruct` to reset.
- **OS Agnostic Logic:** One codebase generates distinct configurations for `darwin/arm64` (Apple Silicon) and `linux/amd64`.
- **Tooling Focus:** Specifically optimized for **Zsh**, **Zellij**, and **Neovim**.

## Project Structure

```text
homestruct/
├── cmd/
│   └── homestruct/
│       ├── main.go         # Entry point, CLI logic
│       └── templates/      # Embedded templates (go:embed)
│           ├── nvim/
│           │   ├── init.lua
│           │   └── lua/    # Lua config modules
│           ├── zellij/
│           │   └── config.kdl.tmpl
│           ├── zsh/
│           │   ├── .zshrc.tmpl
│           │   └── aliases.zsh.tmpl
│           └── git/
│               └── .gitconfig.tmpl
├── pkg/
│   ├── generator/          # Logic for rendering templates
│   └── backup/             # Logic for backing up existing files
├── .github/
│   └── workflows/
│       └── release.yml     # GitHub Actions release automation
├── install.sh              # One-line install script
├── go.mod
├── Makefile
└── README.md
```

## Installation

### Option 1: Install Script (Recommended)

The easiest way to install homestruct is using the install script. It automatically detects your OS and architecture, downloads the appropriate binary, and installs it.

```bash
curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
```

**Customization options:**

```bash
# Install a specific version
HOMESTRUCT_VERSION=v1.0.0 curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh

# Install to a custom directory
HOMESTRUCT_INSTALL=~/bin curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
```

### Option 2: Manual Download

Download the binary for your architecture from the [Releases](https://github.com/nabkey/home-files/releases) page.

**macOS (Apple Silicon):**
```bash
curl -L -o homestruct https://github.com/nabkey/home-files/releases/latest/download/homestruct-darwin-arm64
chmod +x homestruct
sudo mv homestruct /usr/local/bin/
```

**macOS (Intel):**
```bash
curl -L -o homestruct https://github.com/nabkey/home-files/releases/latest/download/homestruct-darwin-amd64
chmod +x homestruct
sudo mv homestruct /usr/local/bin/
```

**Linux (x86_64):**
```bash
curl -L -o homestruct https://github.com/nabkey/home-files/releases/latest/download/homestruct-linux-amd64
chmod +x homestruct
sudo mv homestruct /usr/local/bin/
```

**Linux (ARM64):**
```bash
curl -L -o homestruct https://github.com/nabkey/home-files/releases/latest/download/homestruct-linux-arm64
chmod +x homestruct
sudo mv homestruct /usr/local/bin/
```

### Option 3: Build from Source

Requires Go 1.23+.

```bash
git clone https://github.com/nabkey/home-files
cd home-files
make build
sudo make install
# Or install to ~/.local/bin without sudo:
make install-local
```

## Usage

### 1. Dry Run

Always run with `--dry-run` first to see what files will be created or overwritten.

```bash
homestruct generate --dry-run
```

### 2. Generate (Apply)

This will backup existing files to `~/.homestruct-backup/<timestamp>/` and write the new configurations.

```bash
homestruct generate
```

### 3. Force Overwrite

Skip backup and force generation (destructive).

```bash
homestruct generate --force
```

## Templating Guide

homestruct uses Go's standard `text/template`. We inject a Context struct into every template.

### Available Variables

| Variable | Description |
|----------|-------------|
| `{{ .OS }}` | "darwin" or "linux" |
| `{{ .Arch }}` | "amd64" or "arm64" |
| `{{ .Home }}` | Path to user home directory |
| `{{ .User }}` | Current username |

### Example: Zellij (Handling Command vs Alt)

In `templates/zellij/config.kdl.tmpl`:

```kdl
keybinds {
    normal {
        // Shared bindings
        bind "Ctrl g" { SwitchToMode "Locked"; }

        {{ if eq .OS "darwin" }}
        // MacOS specific: Use Command Key
        bind "Cmd n" { NewPane; }
        bind "Cmd h" { MoveFocus "Left"; }
        {{ else }}
        // Linux specific: Use Alt Key
        bind "Alt n" { NewPane; }
        bind "Alt h" { MoveFocus "Left"; }
        {{ end }}
    }
}
```

### Example: Zsh (Path Differences)

In `templates/zsh/.zshrc.tmpl`:

```zsh
# Common exports
export EDITOR="nvim"

# OS Specific Paths
{{ if eq .OS "darwin" }}
# Brew on Apple Silicon
export PATH="/opt/homebrew/bin:$PATH"
{{ else }}
# Standard Linux Bin
export PATH="/usr/local/bin:$PATH"
{{ end }}
```

## Development Workflow

1. **Modify a template:** Edit a file in `templates/`.
2. **Test the render:** Run `go run ./cmd/homestruct generate --dry-run --verbose`.
3. **Embed:** Since we use `//go:embed templates/*`, simply rebuilding the binary includes your changes.

### Adding a New Tool

1. Create the file in `templates/my-new-tool/config.conf`.
2. Register the mapping in `pkg/generator/map.go`:

```go
var FileMappings = map[string]string{
    "templates/my-new-tool/config.conf": ".config/my-new-tool/config.conf",
}
```

## Release Workflow

Releases are automated via GitHub Actions. When you push a tag, binaries are automatically built and published.

```bash
# Create and push a new release tag
git tag v1.0.0
git push origin v1.0.0
```

For local development, use the Makefile:

```bash
# Build all release binaries to ./dist
make release
```

This creates:
- `dist/homestruct-darwin-arm64` - macOS Apple Silicon
- `dist/homestruct-darwin-amd64` - macOS Intel
- `dist/homestruct-linux-amd64` - Linux x86_64
- `dist/homestruct-linux-arm64` - Linux ARM64

## Notes on Neovim

For Neovim, we copy the entry point `init.lua` and the directory structure.

- **Strategy:** The generator places the `init.lua` file.
- **Package Management:** The first time you open nvim after generation, lazy.nvim will bootstrap itself and download your plugins. homestruct does not manage plugin files directly, only the configuration that declares them.

## License

MIT License - see [LICENSE](LICENSE) for details.
