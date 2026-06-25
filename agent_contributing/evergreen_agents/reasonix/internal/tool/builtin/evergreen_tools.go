// Package builtin registers Evergreen-specific tools with the global reasonix
// built-in registry: experience_query (search experience library) and
// dependency_analyze (module dependency chain analysis).
//
// These tools access the filesystem directly (reading .md cards and YAML configs)
// to avoid circular imports with internal/evergreen/.
package builtin

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"reasonix_gr/internal/tool"
)

func init() {
	tool.RegisterBuiltin(&experienceQueryTool{})
	tool.RegisterBuiltin(&dependencyAnalyzeTool{})
}

// experienceQueryTool searches the experience library for relevant cards.
type experienceQueryTool struct{}

func (experienceQueryTool) Name() string        { return "experience_query" }
func (experienceQueryTool) ReadOnly() bool      { return true }

func (experienceQueryTool) Description() string {
	return `Search the Evergreen experience library for relevant cards (patterns, anti-patterns, constraints, lessons, dead-ends).

Use this before writing code to:
- Find reusable patterns for the task at hand
- Avoid known anti-patterns and dead ends
- Check hard constraints that must be followed

Parameters:
- query: keyword to search in titles, bodies, and tags
- type (optional): filter by card type (pattern, antipattern, constraint, dead_end, lesson)
- module (optional): filter by module name
- tags (optional): comma-separated tag filters
- limit (optional): max results (default 10)`
}

func (experienceQueryTool) Schema() json.RawMessage {
	return json.RawMessage(`{
  "type": "object",
  "properties": {
    "query": {"type": "string", "description": "Keyword to search for in experience cards"},
    "type": {"type": "string", "enum": ["pattern", "antipattern", "constraint", "dead_end", "lesson"]},
    "module": {"type": "string", "description": "Filter by module name (e.g. auth, palace)"},
    "tags": {"type": "string", "description": "Comma-separated tag filters"},
    "limit": {"type": "integer", "default": 10, "description": "Maximum number of results"}
  },
  "required": ["query"]
}`)
}

func (experienceQueryTool) Execute(ctx context.Context, args json.RawMessage) (string, error) {
	var params struct {
		Query  string `json:"query"`
		Type   string `json:"type"`
		Module string `json:"module"`
		Tags   string `json:"tags"`
		Limit  int    `json:"limit"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("experience_query: parse args: %w", err)
	}
	if params.Limit <= 0 {
		params.Limit = 10
	}

	// Search the experiences directory
	experiencesDir := "agent_contributing/experiences"
	entries, err := os.ReadDir(experiencesDir)
	if err != nil {
		return fmt.Sprintf("Experience directory not found: %s", experiencesDir), nil
	}

	queryLower := strings.ToLower(params.Query)
	tagFilters := splitAndTrim(params.Tags, ",")

	type result struct {
		file string
		card experienceCard
		score int
	}
	var results []result

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
			continue
		}

		data, err := os.ReadFile(filepath.Join(experiencesDir, entry.Name()))
		if err != nil {
			continue
		}

		card := parseExperienceCard(string(data), entry.Name())
		if card.ID == "" {
			continue
		}

		// Filters
		if params.Type != "" && card.Type != params.Type {
			continue
		}
		if params.Module != "" && card.Module != params.Module {
			continue
		}
		if len(tagFilters) > 0 {
			hasTag := false
			for _, tf := range tagFilters {
				for _, ct := range card.Tags {
					if ct == tf {
						hasTag = true
						break
					}
				}
			}
			if !hasTag {
				continue
			}
		}

		// Scoring
		score := 0
		if queryLower != "" && strings.Contains(strings.ToLower(card.Title), queryLower) {
			score += 10
		}
		if queryLower != "" && strings.Contains(strings.ToLower(card.Body), queryLower) {
			score += 5
		}
		for _, tag := range card.Tags {
			if queryLower != "" && strings.Contains(strings.ToLower(tag), queryLower) {
				score += 3
			}
		}

		if score > 0 || params.Query == "" {
			results = append(results, result{entry.Name(), card, score})
		}
	}

	// Sort by score descending (simple bubble for n≤50)
	for i := 0; i < len(results); i++ {
		for j := i + 1; j < len(results); j++ {
			if results[j].score > results[i].score {
				results[i], results[j] = results[j], results[i]
			}
		}
	}

	if len(results) > params.Limit {
		results = results[:params.Limit]
	}

	if len(results) == 0 {
		return "No matching experience cards found.", nil
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Found %d experience card(s):\n\n", len(results)))
	for _, r := range results {
		sb.WriteString(fmt.Sprintf("### %s\n", r.card.Title))
		sb.WriteString(fmt.Sprintf("- **Type**: %s\n", r.card.Type))
		if r.card.Module != "" {
			sb.WriteString(fmt.Sprintf("- **Module**: %s\n", r.card.Module))
		}
		if len(r.card.Tags) > 0 {
			sb.WriteString(fmt.Sprintf("- **Tags**: %s\n", strings.Join(r.card.Tags, ", ")))
		}
		sb.WriteString(fmt.Sprintf("- **File**: %s\n", r.file))
		sb.WriteString(fmt.Sprintf("- **Status**: %s\n", r.card.Status))
		if r.card.Body != "" {
			// Show first 300 chars of body
			preview := r.card.Body
			if len(preview) > 300 {
				preview = preview[:300] + "..."
			}
			sb.WriteString(fmt.Sprintf("- **Preview**: %s\n", preview))
		}
		sb.WriteString("\n")
	}
	return sb.String(), nil
}

// dependencyAnalyzeTool reads module_registry.yaml to show dependency chains.
type dependencyAnalyzeTool struct{}

func (dependencyAnalyzeTool) Name() string   { return "dependency_analyze" }
func (dependencyAnalyzeTool) ReadOnly() bool { return true }

func (dependencyAnalyzeTool) Description() string {
	return `Analyze module dependencies from the module registry.

Shows:
- Direct dependencies (depends_on)
- Reverse dependencies (depended_by)
- Active interface contracts for a module
- Dependency chains between modules

Use this before modifying cross-module code to understand impact.

Parameters:
- module: the module name to analyze (e.g. "auth", "palace")
- direction (optional): "forward" (depends_on), "reverse" (depended_by), or "both" (default)`
}

func (dependencyAnalyzeTool) Schema() json.RawMessage {
	return json.RawMessage(`{
  "type": "object",
  "properties": {
    "module": {"type": "string", "description": "Module name to analyze"},
    "direction": {"type": "string", "enum": ["forward", "reverse", "both"], "default": "both"}
  },
  "required": ["module"]
}`)
}

func (dependencyAnalyzeTool) Execute(ctx context.Context, args json.RawMessage) (string, error) {
	var params struct {
		Module    string `json:"module"`
		Direction string `json:"direction"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return "", fmt.Errorf("dependency_analyze: parse args: %w", err)
	}
	if params.Direction == "" {
		params.Direction = "both"
	}

	// Read module_registry.yaml
	registryPath := "agent_contributing/evergreen_agents/config/module_registry.yaml"
	data, err := os.ReadFile(registryPath)
	if err != nil {
		return fmt.Sprintf("Module registry not found: %s", registryPath), nil
	}

	modules := parseModuleRegistry(string(data))

	var target *moduleEntry
	for i := range modules {
		if modules[i].Name == params.Module {
			target = &modules[i]
			break
		}
	}
	if target == nil {
		return fmt.Sprintf("Module '%s' not found in registry. Available modules: %s",
			params.Module, listModuleNames(modules)), nil
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("## Module: %s\n", target.Name))
	sb.WriteString(fmt.Sprintf("- **Section**: %s\n", target.Section))
	sb.WriteString(fmt.Sprintf("- **Status**: %s\n", target.Status))
	sb.WriteString(fmt.Sprintf("- **Path**: %s\n", target.Path))

	if params.Direction == "forward" || params.Direction == "both" {
		sb.WriteString(fmt.Sprintf("\n### Depends On (%d):\n", len(target.DependsOn)))
		if len(target.DependsOn) == 0 {
			sb.WriteString("(none — leaf module)\n")
		}
		for _, dep := range target.DependsOn {
			detail := findModule(modules, dep)
			if detail != nil {
				sb.WriteString(fmt.Sprintf("- **%s** (%s, %s)\n", dep, detail.Section, detail.Status))
			} else {
				sb.WriteString(fmt.Sprintf("- **%s** (not in registry)\n", dep))
			}
		}
	}

	if params.Direction == "reverse" || params.Direction == "both" {
		sb.WriteString(fmt.Sprintf("\n### Depended By (%d):\n", len(target.DependedBy)))
		if len(target.DependedBy) == 0 {
			sb.WriteString("(none — top-level module)\n")
		}
		for _, dep := range target.DependedBy {
			detail := findModule(modules, dep)
			if detail != nil {
				sb.WriteString(fmt.Sprintf("- **%s** (%s, %s)\n", dep, detail.Section, detail.Status))
			} else {
				sb.WriteString(fmt.Sprintf("- **%s** (not in registry)\n", dep))
			}
		}
	}

	// Contracts
	if len(target.Contracts) > 0 {
		sb.WriteString(fmt.Sprintf("\n### Active Contracts (%d):\n", len(target.Contracts)))
		for _, c := range target.Contracts {
			sb.WriteString(fmt.Sprintf("- **%s** ↔ %s\n", c.From, c.To))
		}
	}

	return sb.String(), nil
}

// ---------------------------------------------------------------------------
// Lightweight YAML parsing helpers (avoid dependency on gopkg.in/yaml.v3 in builtin)
// ---------------------------------------------------------------------------

type experienceCard struct {
	ID      string
	Type    string
	Title   string
	Tags    []string
	Module  string
	Status  string
	Body    string
}

type moduleEntry struct {
	Name       string
	Path       string
	Section    string
	Status     string
	DependsOn  []string
	DependedBy []string
	Contracts  []contractEntry
}

type contractEntry struct {
	From string
	To   string
}

func parseExperienceCard(md, filename string) experienceCard {
	card := experienceCard{}
	lines := strings.Split(strings.TrimSpace(md), "\n")
	if len(lines) == 0 || strings.TrimSpace(lines[0]) != "---" {
		return card
	}

	endIdx := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			endIdx = i
			break
		}
	}
	if endIdx < 0 {
		return card
	}

	// Parse frontmatter
	fm := map[string]string{}
	tagList := []string{}
	for i := 1; i < endIdx; i++ {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		if idx := strings.Index(line, ":"); idx >= 0 {
			key := strings.TrimSpace(line[:idx])
			val := strings.TrimSpace(line[idx+1:])
			// Handle tags: [a, b, c]
			if key == "tags" {
				val = strings.Trim(val, "[]")
				for _, t := range strings.Split(val, ",") {
					t = strings.TrimSpace(t)
					t = strings.Trim(t, `"'`)
					if t != "" {
						tagList = append(tagList, t)
					}
				}
			}
			fm[key] = val
		}
	}

	if endIdx+1 < len(lines) {
		card.Body = strings.TrimSpace(strings.Join(lines[endIdx+1:], "\n"))
	}

	// Derive ID from filename
	card.ID = strings.TrimSuffix(filename, ".md")
	card.Type = fm["type"]
	if card.Type == "" {
		card.Type = fm["task_type"]
	}
	card.Title = fm["title"]
	if card.Title == "" {
		card.Title = fm["type"]
	}
	card.Module = fm["module"]
	card.Status = fm["status"]
	if card.Status == "" {
		card.Status = fm["outcome"]
		if card.Status == "success" {
			card.Status = "approved"
		}
	}
	card.Tags = tagList

	return card
}

func parseModuleRegistry(yaml string) []moduleEntry {
	var modules []moduleEntry
	var current *moduleEntry

	lines := strings.Split(yaml, "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") || trimmed == "modules:" || trimmed == "version:" {
			continue
		}

		if strings.HasPrefix(trimmed, "- name:") {
			if current != nil {
				modules = append(modules, *current)
			}
			current = &moduleEntry{}
			current.Name = strings.TrimPrefix(trimmed, "- name:")
			current.Name = strings.TrimSpace(current.Name)
			continue
		}

		if current == nil {
			continue
		}

		if idx := strings.Index(trimmed, ":"); idx >= 0 {
			key := strings.TrimSpace(trimmed[:idx])
			val := strings.TrimSpace(trimmed[idx+1:])

			switch key {
			case "path":
				current.Path = val
			case "section":
				current.Section = val
			case "status":
				current.Status = val
			case "depends_on":
				current.DependsOn = parseListLine(val)
			case "depended_by":
				current.DependedBy = parseListLine(val)
			}
		}
	}
	if current != nil {
		modules = append(modules, *current)
	}

	return modules
}

func parseListLine(val string) []string {
	val = strings.Trim(val, "[]")
	if val == "" {
		return nil
	}
	var result []string
	for _, s := range strings.Split(val, ",") {
		s = strings.TrimSpace(s)
		s = strings.Trim(s, `"'`)
		if s != "" {
			result = append(result, s)
		}
	}
	return result
}

func findModule(modules []moduleEntry, name string) *moduleEntry {
	for i := range modules {
		if modules[i].Name == name {
			return &modules[i]
		}
	}
	return nil
}

func listModuleNames(modules []moduleEntry) string {
	names := make([]string, len(modules))
	for i, m := range modules {
		names[i] = m.Name
	}
	return strings.Join(names, ", ")
}

func splitAndTrim(s, sep string) []string {
	if s == "" {
		return nil
	}
	var result []string
	for _, part := range strings.Split(s, sep) {
		part = strings.TrimSpace(part)
		if part != "" {
			result = append(result, part)
		}
	}
	return result
}
