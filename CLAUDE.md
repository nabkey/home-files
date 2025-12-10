# CLAUDE.md

This file provides context for Claude Code when working with the homestruct codebase.

## Project Overview

homestruct is a Go-based home files generator that compiles templates into a single binary and renders them onto host machines. It handles OS-specific logic (macOS vs Linux) at generation time.

## Build & Run Commands

```bash
# Build the binary
go build -o homestruct ./cmd/homestruct

# Run with dry-run (preview changes)
go run ./cmd/homestruct generate --dry-run

# Run with verbose dry-run
go run ./cmd/homestruct generate --dry-run --verbose

# Generate files (applies changes)
go run ./cmd/homestruct generate

# Force overwrite without backup
go run ./cmd/homestruct generate --force

# Build release binaries
make release
```

## Architecture

### Key Directories

- `cmd/homestruct/` - CLI entry point and command handling
- `templates/` - Source templates embedded into the binary via `//go:embed`
- `pkg/generator/` - Template rendering logic
- `pkg/backup/` - File backup logic before overwriting

### Template System

Templates use Go's `text/template` with these context variables:
- `.OS` - "darwin" or "linux"
- `.Arch` - "amd64" or "arm64"
- `.Home` - User home directory path
- `.User` - Current username

### File Mappings

Template-to-destination mappings are defined in `pkg/generator/map.go`. When adding a new tool config:

1. Add template file(s) to `templates/<tool-name>/`
2. Register mapping in `pkg/generator/map.go`

### Supported Tools

- **Zsh** - Shell configuration (`.zshrc`, aliases)
- **Zellij** - Terminal multiplexer config
- **Neovim** - Editor configuration (`init.lua` and lua modules)
- **Git** - Global git configuration

## Code Style

- Follow standard Go conventions
- Use `text/template` syntax for all `.tmpl` files
- Keep OS-specific logic in templates using `{{ if eq .OS "darwin" }}` conditionals
- Backup destination pattern: `~/.homestruct-backup/<timestamp>/`

## Testing Changes

Always test template changes with `--dry-run --verbose` before applying to verify:
1. Correct file paths are targeted
2. Template variables render correctly for both darwin and linux
3. No syntax errors in templates

## Commit Convention & Releases

This project uses **semantic releases** triggered automatically on merge to `main`. Use conventional commit format:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Commit Types

| Type | Release | Description |
|------|---------|-------------|
| `feat` | Minor | New feature or template |
| `fix` | Patch | Bug fix |
| `perf` | Patch | Performance improvement |
| `refactor` | Patch | Code refactoring |
| `docs` | Patch | Documentation only |
| `test` | Patch | Adding/updating tests |
| `chore` | Patch | Maintenance tasks |
| `build` | Patch | Build system changes |
| `ci` | Patch | CI/CD changes |

### Breaking Changes

For major version bumps, use either:
- `feat!: description` (with `!` suffix)
- Include `BREAKING CHANGE:` in commit footer

### Examples

```bash
# Feature (minor bump)
git commit -m "feat(zsh): add fzf integration aliases"

# Bug fix (patch bump)
git commit -m "fix(nvim): correct treesitter config path"

# Breaking change (major bump)
git commit -m "feat!: change template variable names"
```

Commits without conventional prefixes will not trigger a release.
