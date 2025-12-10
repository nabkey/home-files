package generator

import (
	"bytes"
	"embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

// Generator handles template rendering and file generation.
type Generator struct {
	templates embed.FS
	ctx       *Context
	verbose   bool
}

// New creates a new Generator with the given embedded templates.
func New(templates embed.FS, verbose bool) (*Generator, error) {
	ctx, err := NewContext()
	if err != nil {
		return nil, fmt.Errorf("failed to create context: %w", err)
	}

	return &Generator{
		templates: templates,
		ctx:       ctx,
		verbose:   verbose,
	}, nil
}

// Result represents the result of processing a single file.
type Result struct {
	TemplatePath string
	DestPath     string
	Content      string
	Exists       bool
}

// Generate processes all templates and returns the results.
func (g *Generator) Generate() ([]Result, error) {
	var results []Result

	for templatePath, destRelPath := range FileMappings {
		content, err := g.templates.ReadFile(templatePath)
		if err != nil {
			return nil, fmt.Errorf("failed to read template %s: %w", templatePath, err)
		}

		rendered, err := g.renderTemplate(templatePath, string(content))
		if err != nil {
			return nil, fmt.Errorf("failed to render template %s: %w", templatePath, err)
		}

		destPath := filepath.Join(g.ctx.Home, destRelPath)

		exists := false
		if _, err := os.Stat(destPath); err == nil {
			exists = true
		}

		results = append(results, Result{
			TemplatePath: templatePath,
			DestPath:     destPath,
			Content:      rendered,
			Exists:       exists,
		})
	}

	return results, nil
}

// renderTemplate processes a template string with the context.
func (g *Generator) renderTemplate(name, content string) (string, error) {
	// Only process .tmpl files as templates
	if !strings.HasSuffix(name, ".tmpl") {
		return content, nil
	}

	tmpl, err := template.New(name).Parse(content)
	if err != nil {
		return "", err
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, g.ctx); err != nil {
		return "", err
	}

	return buf.String(), nil
}

// WriteFile writes a result to disk, creating directories as needed.
func (g *Generator) WriteFile(r Result) error {
	dir := filepath.Dir(r.DestPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory %s: %w", dir, err)
	}

	if err := os.WriteFile(r.DestPath, []byte(r.Content), 0644); err != nil {
		return fmt.Errorf("failed to write file %s: %w", r.DestPath, err)
	}

	return nil
}

// Context returns the generator's context.
func (g *Generator) Context() *Context {
	return g.ctx
}
