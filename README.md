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
│       └── main.go         # Entry point, CLI logic
├── templates/              # The raw source of truth
│   ├── nvim/
│   │   ├── init.lua
│   │   └── lua/            # Recursive Lua folders
│   ├── zellij/
│   │   └── config.kdl.tmpl # Templated for Mac/Linux keybinds
│   ├── zsh/
│   │   ├── .zshrc.tmpl
│   │   └── aliases.zsh.tmpl
│   └── git/
│       └── .gitconfig.tmpl
├── pkg/
│   ├── generator/          # Logic for rendering templates
│   └── backup/             # Logic for backing up existing files
├── go.mod
├── Makefile
└── README.md
```

## Installation

### Option 1: Install Script (Recommended)

The easiest way to install config files is using the install script. It downloads pre-generated configs for your OS and installs them to your home directory.

```bash
curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
```

**Preview what will be installed (dry run):**
```bash
curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_DRY_RUN=true sh
```

**Install without confirmation prompt:**
```bash
curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_FORCE=true sh
```

**Install a specific version:**
```bash
curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_VERSION=v1.0.0 sh
```

**Install without creating backups:**
```bash
curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_BACKUP=false sh
```

### Option 2: Download Binary

For more control, download the `homestruct` binary and run it manually.

**macOS (Apple Silicon):**
```bash
curl -L -o homestruct https://github.com/nabkey/home-files/releases/latest/download/homestruct-darwin-arm64
chmod +x homestruct
./homestruct generate
```

**Linux:**
```bash
curl -L -o homestruct https://github.com/nabkey/home-files/releases/latest/download/homestruct-linux-amd64
chmod +x homestruct
./homestruct generate
```

### Option 3: Build from Source

Requires Go 1.23+.

```bash
git clone https://github.com/nabkey/home-files
cd home-files
go build -o homestruct ./cmd/homestruct
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

### Automated Releases (GitHub Actions)

Releases are automatically built and published when you push a version tag:

```bash
# Create and push a version tag
git tag v1.0.0
git push origin v1.0.0
```

This triggers the GitHub Actions release workflow which:
1. Runs tests
2. Builds binaries for darwin/arm64 and linux/amd64
3. Generates pre-rendered config archives for each OS
4. Generates SHA256 checksums
5. Creates a GitHub release with all artifacts

### Manual Release Build

You can also build release artifacts locally using the Makefile:

```bash
# Build binaries to ./dist
make release

# Generate config archives to ./dist
make release-configs

# Generate checksums
make release-checksums
```

**Release artifacts:**
- `dist/homestruct-darwin-arm64` - Binary for macOS
- `dist/homestruct-linux-amd64` - Binary for Linux
- `dist/configs-darwin.tar.gz` - Pre-rendered configs for macOS
- `dist/configs-linux.tar.gz` - Pre-rendered configs for Linux
- `dist/checksums.txt` - SHA256 checksums for verification

## Notes on Neovim

For Neovim, we copy the entry point `init.lua` and the directory structure.

- **Strategy:** The generator places the `init.lua` file.
- **Package Management:** The first time you open nvim after generation, lazy.nvim will bootstrap itself and download your plugins. homestruct does not manage plugin files directly, only the configuration that declares them.

## License

MIT License - see [LICENSE](LICENSE) for details.
