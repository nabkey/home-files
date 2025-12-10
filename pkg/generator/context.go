package generator

import (
	"os"
	"os/user"
	"runtime"
)

// Context provides template variables for rendering.
type Context struct {
	OS   string // "darwin" or "linux"
	Arch string // "amd64" or "arm64"
	Home string // User home directory path
	User string // Current username
}

// NewContext creates a new Context with system information.
// Environment variables HOMESTRUCT_OS and HOMESTRUCT_ARCH can override
// the detected values (useful for generating configs for other platforms).
func NewContext() (*Context, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	currentUser, err := user.Current()
	if err != nil {
		return nil, err
	}

	// Allow environment variable overrides for cross-platform config generation
	osVal := os.Getenv("HOMESTRUCT_OS")
	if osVal == "" {
		osVal = runtime.GOOS
	}

	archVal := os.Getenv("HOMESTRUCT_ARCH")
	if archVal == "" {
		archVal = runtime.GOARCH
	}

	return &Context{
		OS:   osVal,
		Arch: archVal,
		Home: homeDir,
		User: currentUser.Username,
	}, nil
}
