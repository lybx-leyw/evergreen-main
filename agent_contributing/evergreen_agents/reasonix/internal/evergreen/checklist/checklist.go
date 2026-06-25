// Package checklist generates and manages per-module REVIEW_CHECKLIST.md files.
// Each checklist is a machine-readable + human-readable list of review items
// derived from the experience library — turning past lessons into mandatory
// pre-merge checks.
//
// The Keeper injects the checklist into its review prompt, ensuring every
// change is checked against known patterns/anti-patterns/constraints.
package checklist

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"reasonix_gr/internal/evergreen/experience"
)

// Item is a single checklist entry.
type Item struct {
	ID       string // stable identifier, e.g. "CHK-auth-001"
	Category string // security | performance | pattern | antipattern | contract
	Check    string // the check description (actionable)
	Why      string // why this matters
	Source   string // which experience card this came from
	Severity string // must | should | may
}

// ModuleChecklist is the full checklist for one module.
type ModuleChecklist struct {
	Module string
	Items  []Item
	Stats  ChecklistStats
}

// ChecklistStats summarizes a checklist.
type ChecklistStats struct {
	Total    int
	Must     int
	Should   int
	May      int
	ByCat    map[string]int
}

// Generate creates a REVIEW_CHECKLIST.md for a module from the experience store.
func Generate(module string, store *experience.Store) *ModuleChecklist {
	patterns, antipatterns, constraints := store.InjectForTask(module, "")

	cl := &ModuleChecklist{
		Module: module,
		Stats:  ChecklistStats{ByCat: make(map[string]int)},
	}

	id := func(prefix string, n int) string {
		return fmt.Sprintf("CHK-%s-%03d", strings.ToUpper(module), n)
	}

	// 1. Hard constraints → "must" items
	for i, c := range constraints {
		cl.Items = append(cl.Items, Item{
			ID:       id("C", i+1),
			Category: "constraint",
			Check:    fmt.Sprintf("Verify: %s", c.Title),
			Why:      c.Body,
			Source:   c.ID,
			Severity: "must",
		})
	}

	// 2. Anti-patterns → "must" items
	for i, a := range antipatterns {
		cl.Items = append(cl.Items, Item{
			ID:       id("A", i+1),
			Category: "antipattern",
			Check:    fmt.Sprintf("Avoid: %s", a.Title),
			Why:      a.Body,
			Source:   a.ID,
			Severity: "must",
		})
	}

	// 3. Patterns → "should" items
	for i, p := range patterns {
		cl.Items = append(cl.Items, Item{
			ID:       id("P", i+1),
			Category: "pattern",
			Check:    fmt.Sprintf("Prefer: %s", p.Title),
			Why:      p.Body,
			Source:   p.ID,
			Severity: "should",
		})
	}

	// 4. Universal checks (always apply)
	universal := []Item{
		{ID: id("U", 1), Category: "security", Check: "No hardcoded secrets or API keys", Why: "Secrets must be injected via env vars or config", Severity: "must"},
		{ID: id("U", 2), Category: "performance", Check: "No N+1 queries or unbounded loops", Why: "Performance regression prevention", Severity: "must"},
		{ID: id("U", 3), Category: "testing", Check: "New code has corresponding tests", Why: "Maintain test coverage ≥ 80%", Severity: "must"},
		{ID: id("U", 4), Category: "docs", Check: "Public API has documentation", Why: "Every exported function needs a doc comment", Severity: "should"},
		{ID: id("U", 5), Category: "contract", Check: "No breaking changes to module interface", Why: "Check contracts in module_registry.yaml", Severity: "must"},
		{ID: id("U", 6), Category: "logging", Check: "Errors are logged with context", Why: "Production debugging requires structured logs", Severity: "should"},
	}
	cl.Items = append(cl.Items, universal...)

	// Compute stats
	for _, item := range cl.Items {
		cl.Stats.Total++
		switch item.Severity {
		case "must":
			cl.Stats.Must++
		case "should":
			cl.Stats.Should++
		case "may":
			cl.Stats.May++
		}
		cl.Stats.ByCat[item.Category]++
	}

	// Sort: must first, then should, then may
	sort.Slice(cl.Items, func(i, j int) bool {
		order := map[string]int{"must": 0, "should": 1, "may": 2}
		return order[cl.Items[i].Severity] < order[cl.Items[j].Severity]
	})

	return cl
}

// ToMarkdown renders the checklist as REVIEW_CHECKLIST.md content.
func (cl *ModuleChecklist) ToMarkdown() string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("# REVIEW_CHECKLIST — %s\n\n", cl.Module))
	b.WriteString("> Auto-generated from the experience library.\n")
	b.WriteString("> Keeper must verify ALL `must` items before approving.\n\n")

	b.WriteString(fmt.Sprintf("**%d checks** (%d must, %d should, %d may)\n\n",
		cl.Stats.Total, cl.Stats.Must, cl.Stats.Should, cl.Stats.May))

	// Group by category
	categories := []string{"constraint", "antipattern", "pattern", "security", "performance", "testing", "contract", "docs", "logging"}
	catNames := map[string]string{
		"constraint":   "🔴 Hard Constraints",
		"antipattern":  "⚠️ Anti-patterns to Avoid",
		"pattern":      "✅ Recommended Patterns",
		"security":     "🔒 Security",
		"performance":  "⚡ Performance",
		"testing":      "🧪 Testing",
		"contract":     "📜 Interface Contracts",
		"docs":         "📝 Documentation",
		"logging":      "📊 Logging & Observability",
	}

	for _, cat := range categories {
		var items []Item
		for _, item := range cl.Items {
			if item.Category == cat {
				items = append(items, item)
			}
		}
		if len(items) == 0 {
			continue
		}

		b.WriteString(fmt.Sprintf("## %s\n\n", catNames[cat]))
		for _, item := range items {
			badge := map[string]string{"must": "MUST", "should": "SHOULD", "may": "MAY"}[item.Severity]
			b.WriteString(fmt.Sprintf("- [ ] **[%s]** %s\n", badge, item.Check))
			if item.Why != "" {
				b.WriteString(fmt.Sprintf("  - *Why:* %s\n", item.Why))
			}
		}
		b.WriteString("\n")
	}

	return b.String()
}

// WriteToFile writes the checklist to disk.
func (cl *ModuleChecklist) WriteToFile(path string) error {
	return os.WriteFile(path, []byte(cl.ToMarkdown()), 0644)
}

// ToPromptInjection returns the checklist formatted for injection into the
// Keeper's system prompt during review.
func (cl *ModuleChecklist) ToPromptInjection() string {
	var b strings.Builder
	b.WriteString("## Review Checklist for this module\n\n")
	b.WriteString("Verify ALL `must` items before approving:\n\n")

	for _, item := range cl.Items {
		if item.Severity != "must" {
			continue
		}
		b.WriteString(fmt.Sprintf("- [ ] **%s**: %s\n", item.ID, item.Check))
	}

	return b.String()
}
