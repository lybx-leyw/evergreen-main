// Package inspector implements the Inspector agent — a read-only code health
// scanner. It scans the codebase for anti-patterns, tech debt, contract
// violations, and code quality issues. Falls back to rule-based detection
// when the LLM is unavailable. Uses the quick-thinking LLM tier.
//
// Ported from src/agents/inspector.py.
package inspector

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"reasonix_gr/internal/agent"
	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/contracts"
	"reasonix_gr/internal/evergreen/experience"
	"reasonix_gr/internal/evergreen/types"
	"reasonix_gr/internal/provider"
	"reasonix_gr/internal/tool"
)

// Inspector is the code health scanner agent. It implements agent.Runner.
type Inspector struct {
	identity  types.AgentIdentity
	prov      provider.Provider
	registry  *tool.Registry
	session   *agent.Session
	sink      event.Sink
	store     *experience.Store
	validator *contracts.Validator
}

// New creates an Inspector agent.
func New(
	identity types.AgentIdentity,
	prov provider.Provider,
	registry *tool.Registry,
	session *agent.Session,
	sink event.Sink,
	store *experience.Store,
	validator *contracts.Validator,
) *Inspector {
	return &Inspector{
		identity:  identity,
		prov:      prov,
		registry:  registry,
		session:   session,
		sink:      sink,
		store:     store,
		validator: validator,
	}
}

// Identity returns the inspector's agent identity.
func (i *Inspector) Identity() types.AgentIdentity { return i.identity }

// Run implements agent.Runner. Performs a code health scan.
func (i *Inspector) Run(ctx context.Context, input string) error {
	i.sink.Emit(event.Event{
		Kind: event.Phase,
		Text: "inspector · code health scan",
		Federation: &event.FederationPayload{
			System: &event.FederationSystem{AgentID: i.identity.AgentID},
		},
	})

	switch {
	case strings.Contains(input, "scan"):
		return i.fullScan(ctx, input)
	case strings.Contains(input, "antipatterns"):
		return i.scanAntipatterns(ctx, input)
	case strings.Contains(input, "contracts"):
		return i.scanContracts(ctx, input)
	default:
		return i.ruleBasedScan(ctx, input)
	}
}

// fullScan performs a comprehensive LLM-driven code health scan.
func (i *Inspector) fullScan(ctx context.Context, input string) error {
	module := i.extractField(input, "module")
	if module == "" {
		module = "all"
	}

	files := i.gatherFiles(module)

	if len(files) == 0 {
		i.sink.Emit(event.Event{
			Kind: event.Text,
			Text: fmt.Sprintf("No files found for module: %s", module),
		})
		i.sink.Emit(event.Event{Kind: event.TurnDone})
		return nil
	}

	// Load anti-patterns for context
	antipatterns := i.store.SearchConstraints(module)

	// Build scan prompt
	prompt := i.buildScanPrompt(module, files, antipatterns)

	i.session.Add(provider.Message{Role: "user", Content: prompt})

	req := provider.Request{
		Messages:    i.session.Messages,
		Tools:       i.registry.Schemas(),
		Temperature: 0.3,
		MaxTokens:   8192,
	}

	stream, err := i.prov.Stream(ctx, req)
	if err != nil {
		// Fallback to rule-based
		report := i.ruleBasedScanReport(module, files)
		reportJSON, _ := json.MarshalIndent(report, "", "  ")
		i.sink.Emit(event.Event{Kind: event.Text, Text: string(reportJSON)})
		i.sink.Emit(event.Event{Kind: event.TurnDone})
		return nil
	}

	var fullText strings.Builder
	for chunk := range stream {
		if chunk.Text != "" {
			fullText.WriteString(chunk.Text)
			i.sink.Emit(event.Event{Kind: event.Text, Text: chunk.Text})
		}
	}

	i.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// scanAntipatterns checks for known anti-patterns using the experience library.
func (i *Inspector) scanAntipatterns(ctx context.Context, input string) error {
	module := i.extractField(input, "module")
	_ = i.gatherFiles(module) // collect file list for context

	antipatterns := i.store.SearchConstraints(module)

	var findings []string
	for _, ap := range antipatterns {
		findings = append(findings, fmt.Sprintf("- **%s**: %s", ap.Title, ap.Body))
	}

	result := fmt.Sprintf("## Anti-pattern Scan: %s\n\n%d anti-pattern(s) in library:\n%s",
		module, len(antipatterns), strings.Join(findings, "\n"))

	i.sink.Emit(event.Event{Kind: event.Text, Text: result})
	i.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// scanContracts checks for contract violations.
func (i *Inspector) scanContracts(ctx context.Context, input string) error {
	module := i.extractField(input, "module")
	files := i.gatherFiles(module)

	if i.validator == nil {
		i.sink.Emit(event.Event{Kind: event.Text, Text: "Contract validator not configured."})
		i.sink.Emit(event.Event{Kind: event.TurnDone})
		return nil
	}

	violations := i.validator.ValidateChange(module, files, nil)

	result := fmt.Sprintf("## Contract Scan: %s\n\n%d violation(s) found.", module, len(violations))
	for _, v := range violations {
		result += fmt.Sprintf("\n- **[%s]** %s (%s → %s) in %s: %s",
			v.Severity, v.ContractID, v.FromModule, v.ToModule, v.File, v.Message)
	}

	i.sink.Emit(event.Event{Kind: event.Text, Text: result})
	i.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// ruleBasedScan performs a fast rule-based scan without LLM.
func (i *Inspector) ruleBasedScan(ctx context.Context, input string) error {
	module := i.extractField(input, "module")
	files := i.gatherFiles(module)

	report := i.ruleBasedScanReport(module, files)
	reportJSON, _ := json.MarshalIndent(report, "", "  ")

	i.sink.Emit(event.Event{Kind: event.Text, Text: string(reportJSON)})
	i.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// ruleBasedScanReport performs rule-based detection of common anti-patterns.
// This is the fallback when LLM is unavailable.
func (i *Inspector) ruleBasedScanReport(module string, files []string) types.InspectorReport {
	report := types.InspectorReport{
		ModulesScanned: []string{module},
		OverallHealth:  "healthy",
	}

	rules := []struct {
		name     string
		pattern  string
		message  string
		category string
		severity string
	}{
		{"print_statements", "print(", "print() statement found — use proper logging", "code", "low"},
		{"navigator_pop_in_build", "Navigator.pop(context", "Navigator.pop() in build frame may cause issues", "code", "medium"},
		{"missing_mounted_check", "setState(", "setState() without mounted guard — risk after dispose", "code", "high"},
		{"raw_dio_client", "Dio()", "Raw Dio() instantiation — use project Dio client", "code", "high"},
		{"hardcoded_cookies", "Cookie(", "Hardcoded Cookie — use session manager", "code", "high"},
	}

	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			continue
		}
		content := string(data)

		for _, rule := range rules {
			if strings.Contains(content, rule.pattern) {
				count := strings.Count(content, rule.pattern)
				report.TechDebtItems = append(report.TechDebtItems, types.TechDebtItem{
					Location:          fmt.Sprintf("%s (×%d)", file, count),
					Type:              rule.category,
					Description:       rule.message,
					Severity:          rule.severity,
					EstimatedFixCost:  "small",
					DailyInterest:     fmt.Sprintf("%d occurrences", count),
					RecommendedAction: fmt.Sprintf("Replace with proper pattern: %s", rule.name),
				})
			}
		}
	}

	if len(report.TechDebtItems) > 10 {
		report.OverallHealth = "critical"
	} else if len(report.TechDebtItems) > 5 {
		report.OverallHealth = "concerning"
	}

	report.Summary = fmt.Sprintf("Found %d tech debt items across %d files in module '%s'.",
		len(report.TechDebtItems), len(files), module)

	return report
}

// buildScanPrompt constructs the LLM prompt for a full code health scan.
func (i *Inspector) buildScanPrompt(module string, files []string, constraints []*types.ExperienceCard) string {
	var sb strings.Builder
	sb.WriteString("You are the Inspector agent — a read-only code health scanner.\n\n")
	sb.WriteString(fmt.Sprintf("## Scan Target\nModule: %s\nFiles: %d\n\n", module, len(files)))

	sb.WriteString("## Scanned Files (first 30)\n")
	for j, f := range files {
		if j >= 30 {
			sb.WriteString(fmt.Sprintf("... and %d more files\n", len(files)-30))
			break
		}
		sb.WriteString(fmt.Sprintf("- %s\n", f))
	}
	sb.WriteString("\n")

	if len(constraints) > 0 {
		sb.WriteString("## Known Constraints\n")
		for _, c := range constraints {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", c.Title, c.Body))
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Instructions\n")
	sb.WriteString("Scan the module for:\n")
	sb.WriteString("1. Tech debt (code/design/test/docs/infrastructure)\n")
	sb.WriteString("2. Anti-patterns (print statements, missing mounted checks, raw clients)\n")
	sb.WriteString("3. Contract violations\n")
	sb.WriteString("4. Overall health assessment (healthy/concerning/critical)\n\n")
	sb.WriteString("Respond with a JSON InspectorReport.")

	return sb.String()
}

// gatherFiles collects file paths for a module.
func (i *Inspector) gatherFiles(module string) []string {
	var basePath string
	if module != "" && module != "all" {
		basePath = filepath.Join("lib", "features", module)
	} else {
		basePath = "lib"
	}

	var files []string
	filepath.WalkDir(basePath, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if d.Name() == ".git" || d.Name() == "node_modules" || d.Name() == "__pycache__" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, ".dart") || strings.HasSuffix(path, ".go") || strings.HasSuffix(path, ".py") {
			files = append(files, path)
		}
		return nil
	})

	// Cap at 100 files to keep prompts reasonable
	if len(files) > 100 {
		files = files[:100]
	}
	return files
}

func (i *Inspector) extractField(input, field string) string {
	prefix := field + ":"
	for _, line := range strings.Split(input, "\n") {
		if idx := strings.Index(line, prefix); idx >= 0 {
			return strings.TrimSpace(line[idx+len(prefix):])
		}
	}
	return ""
}

// Session returns the agent's session.
func (i *Inspector) Session() *agent.Session { return i.session }
