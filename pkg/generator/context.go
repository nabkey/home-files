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
func NewContext() (*Context, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	currentUser, err := user.Current()
	if err != nil {
		return nil, err
	}

	return &Context{
		OS:   runtime.GOOS,
		Arch: runtime.GOARCH,
		Home: homeDir,
		User: currentUser.Username,
	}, nil
}
