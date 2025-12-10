package backup

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Manager handles file backups.
type Manager struct {
	homeDir   string
	backupDir string
}

// New creates a new backup Manager.
func New(homeDir string) *Manager {
	timestamp := time.Now().Format("20060102-150405")
	backupDir := filepath.Join(homeDir, ".homestruct-backup", timestamp)

	return &Manager{
		homeDir:   homeDir,
		backupDir: backupDir,
	}
}

// BackupFile creates a backup of the given file if it exists.
// Returns the backup path if a backup was created, empty string otherwise.
func (m *Manager) BackupFile(filePath string) (string, error) {
	// Check if file exists
	info, err := os.Stat(filePath)
	if os.IsNotExist(err) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("failed to stat file %s: %w", filePath, err)
	}

	// Skip directories
	if info.IsDir() {
		return "", nil
	}

	// Calculate relative path from home for backup structure
	relPath, err := filepath.Rel(m.homeDir, filePath)
	if err != nil {
		return "", fmt.Errorf("failed to get relative path: %w", err)
	}

	backupPath := filepath.Join(m.backupDir, relPath)

	// Create backup directory structure
	if err := os.MkdirAll(filepath.Dir(backupPath), 0755); err != nil {
		return "", fmt.Errorf("failed to create backup directory: %w", err)
	}

	// Copy file to backup location
	if err := copyFile(filePath, backupPath); err != nil {
		return "", fmt.Errorf("failed to copy file to backup: %w", err)
	}

	return backupPath, nil
}

// BackupDir returns the backup directory path.
func (m *Manager) BackupDir() string {
	return m.backupDir
}

// copyFile copies a file from src to dst.
func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, sourceFile); err != nil {
		return err
	}

	// Preserve file permissions
	sourceInfo, err := os.Stat(src)
	if err != nil {
		return err
	}

	return os.Chmod(dst, sourceInfo.Mode())
}
