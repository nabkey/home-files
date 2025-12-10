package main

import (
	"embed"
	"flag"
	"fmt"
	"os"

	"github.com/nabkey/home-files/pkg/backup"
	"github.com/nabkey/home-files/pkg/generator"
)

//go:embed all:templates
var templates embed.FS

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "generate":
		if err := runGenerate(os.Args[2:]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "help", "-h", "--help":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`homestruct - Home Files Generator

Usage:
  homestruct <command> [options]

Commands:
  generate    Generate configuration files
  help        Show this help message

Generate Options:
  --dry-run   Preview changes without writing files
  --verbose   Show detailed output
  --force     Skip backup and force overwrite`)
}

func runGenerate(args []string) error {
	fs := flag.NewFlagSet("generate", flag.ExitOnError)
	dryRun := fs.Bool("dry-run", false, "Preview changes without writing files")
	verbose := fs.Bool("verbose", false, "Show detailed output")
	force := fs.Bool("force", false, "Skip backup and force overwrite")

	if err := fs.Parse(args); err != nil {
		return err
	}

	gen, err := generator.New(templates, *verbose)
	if err != nil {
		return fmt.Errorf("failed to initialize generator: %w", err)
	}

	ctx := gen.Context()
	fmt.Printf("homestruct - generating for %s/%s\n", ctx.OS, ctx.Arch)
	fmt.Printf("Home directory: %s\n", ctx.Home)
	fmt.Printf("User: %s\n\n", ctx.User)

	results, err := gen.Generate()
	if err != nil {
		return fmt.Errorf("failed to generate files: %w", err)
	}

	if *dryRun {
		fmt.Println("=== DRY RUN MODE ===")
		fmt.Println()
	}

	var backupMgr *backup.Manager
	if !*force && !*dryRun {
		backupMgr = backup.New(ctx.Home)
	}

	var backedUp []string
	for _, r := range results {
		status := "CREATE"
		if r.Exists {
			status = "UPDATE"
		}

		fmt.Printf("[%s] %s\n", status, r.DestPath)

		if *verbose {
			fmt.Printf("  Source: %s\n", r.TemplatePath)
			if *dryRun {
				fmt.Println("  --- Content Preview ---")
				// Show first 500 chars of content
				preview := r.Content
				if len(preview) > 500 {
					preview = preview[:500] + "\n  ... (truncated)"
				}
				fmt.Println(preview)
				fmt.Println("  --- End Preview ---")
			}
		}

		if *dryRun {
			continue
		}

		// Backup existing file if not forcing
		if backupMgr != nil && r.Exists {
			backupPath, err := backupMgr.BackupFile(r.DestPath)
			if err != nil {
				return fmt.Errorf("failed to backup %s: %w", r.DestPath, err)
			}
			if backupPath != "" {
				backedUp = append(backedUp, backupPath)
				if *verbose {
					fmt.Printf("  Backed up to: %s\n", backupPath)
				}
			}
		}

		// Write the file
		if err := gen.WriteFile(r); err != nil {
			return err
		}
	}

	fmt.Println()
	if *dryRun {
		fmt.Printf("Would process %d files (dry run - no changes made)\n", len(results))
	} else {
		fmt.Printf("Successfully generated %d files\n", len(results))
		if len(backedUp) > 0 {
			fmt.Printf("Backed up %d existing files to: %s\n", len(backedUp), backupMgr.BackupDir())
		}
	}

	return nil
}
