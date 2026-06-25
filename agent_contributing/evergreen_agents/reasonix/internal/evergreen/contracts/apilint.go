package contracts

import (
	"fmt"
	"strings"
)

// APILinter checks interface contracts for compatibility violations:
//   - Breaking changes (removed fields, changed types)
//   - Naming convention violations
//   - Missing deprecation markers
//   - Contract version mismatches

// LintResult is a single lint finding.
type LintResult struct {
	Rule     string // which rule triggered
	Severity string // error | warning | info
	Message  string
	File     string
	Line     int
	Fix      string // suggested fix
}

// CompatCheck checks whether a change to a contract is backward-compatible.
type CompatCheck struct {
	ContractID string
	Field      string
	OldValue   string
	NewValue   string
	Breaking   bool
	Reason     string
}

// LintContract validates a single contract for common issues.
func LintContract(contractID, specJSON string) []LintResult {
	var results []LintResult

	// Rule: Contract must have a version
	if !strings.Contains(specJSON, `"version"`) && !strings.Contains(specJSON, `version:`) {
		results = append(results, LintResult{
			Rule:     "contract/require-version",
			Severity: "warning",
			Message:  fmt.Sprintf("Contract %s has no version field — add one for compatibility tracking", contractID),
			Fix:      "Add `\"version\": \"1.0.0\"` to the contract spec",
		})
	}

	// Rule: No deprecated fields without annotation
	if strings.Contains(specJSON, "deprecated") {
		if !strings.Contains(specJSON, "@deprecated") && !strings.Contains(specJSON, "deprecation_note") {
			results = append(results, LintResult{
				Rule:     "contract/deprecation-no-note",
				Severity: "warning",
				Message:  fmt.Sprintf("Contract %s marks fields as deprecated without a deprecation_note", contractID),
				Fix:      "Add `\"deprecation_note\": \"reason and migration path\"`",
			})
		}
	}

	// Rule: Naming convention — should use snake_case
	if strings.Contains(specJSON, "camelCase") || hasCamelCaseFields(specJSON) {
		results = append(results, LintResult{
			Rule:     "contract/naming-convention",
			Severity: "info",
			Message:  fmt.Sprintf("Contract %s uses camelCase field names — prefer snake_case for API contracts", contractID),
			Fix:      "Rename fields to snake_case (e.g. `userId` → `user_id`)",
		})
	}

	return results
}

// CheckCompatibility checks whether newSpec is backward-compatible with oldSpec.
func CheckCompatibility(contractID string, oldSpec, newSpec map[string]interface{}) []CompatCheck {
	var checks []CompatCheck

	for key, newVal := range newSpec {
		oldVal, exists := oldSpec[key]
		if !exists {
			// New field added — compatible (additive)
			checks = append(checks, CompatCheck{
				ContractID: contractID,
				Field:      key,
				NewValue:   fmt.Sprintf("%v", newVal),
				Breaking:   false,
				Reason:     "new field added (additive change, backward-compatible)",
			})
			continue
		}

		// Field exists in both — check type compatibility
		oldType := typeName(oldVal)
		newType := typeName(newVal)
		if oldType != newType {
			checks = append(checks, CompatCheck{
				ContractID: contractID,
				Field:      key,
				OldValue:   fmt.Sprintf("%v (%s)", oldVal, oldType),
				NewValue:   fmt.Sprintf("%v (%s)", newVal, newType),
				Breaking:   true,
				Reason:     fmt.Sprintf("type changed from %s to %s — BREAKING CHANGE", oldType, newType),
			})
		}
	}

	// Check for removed fields
	for key, oldVal := range oldSpec {
		if _, exists := newSpec[key]; !exists {
			checks = append(checks, CompatCheck{
				ContractID: contractID,
				Field:      key,
				OldValue:   fmt.Sprintf("%v", oldVal),
				Breaking:   true,
				Reason:     "field removed — BREAKING CHANGE. Mark as deprecated first, remove in next major version.",
			})
		}
	}

	return checks
}

// HasBreakingChanges returns true if any compatibility check is breaking.
func HasBreakingChanges(checks []CompatCheck) bool {
	for _, c := range checks {
		if c.Breaking {
			return true
		}
	}
	return false
}

// FormatCompatReport formats compatibility checks as a human-readable report.
func FormatCompatReport(checks []CompatCheck) string {
	if len(checks) == 0 {
		return "✅ No compatibility issues found."
	}

	var b strings.Builder
	breaking := 0
	for _, c := range checks {
		if c.Breaking {
			breaking++
		}
	}

	if breaking > 0 {
		b.WriteString(fmt.Sprintf("🚫 %d BREAKING CHANGE(S) detected:\n\n", breaking))
	} else {
		b.WriteString("✅ Backward-compatible changes:\n\n")
	}

	for _, c := range checks {
		icon := "✅"
		if c.Breaking {
			icon = "🚫"
		}
		b.WriteString(fmt.Sprintf("%s **%s**: %s\n", icon, c.Field, c.Reason))
	}

	if breaking > 0 {
		b.WriteString("\n⚠️  Breaking changes require:\n")
		b.WriteString("  1. Both FROM and TO module owner approval\n")
		b.WriteString("  2. Deprecation notice in the old contract version\n")
		b.WriteString("  3. Migration guide for downstream consumers\n")
	}

	return b.String()
}

// LintAllContracts runs all lint rules against all contracts in a model.
func LintAllContracts(model *Model) map[string][]LintResult {
	results := make(map[string][]LintResult)
	for _, c := range model.ListAll() {
		specJSON := fmt.Sprintf("%v", c.InterfaceSpec)
		findings := LintContract(c.ContractID, specJSON)
		if len(findings) > 0 {
			results[c.ContractID] = findings
		}
	}
	return results
}

func typeName(v interface{}) string {
	switch v.(type) {
	case string:
		return "string"
	case float64, float32, int, int64, int32:
		return "number"
	case bool:
		return "boolean"
	case map[string]interface{}:
		return "object"
	case []interface{}:
		return "array"
	default:
		return fmt.Sprintf("%T", v)
	}
}

func hasCamelCaseFields(specJSON string) bool {
	// Quick heuristic: look for patterns like "userId", "createdAt" in keys
	for _, line := range strings.Split(specJSON, "\n") {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "\":") {
			// Extract key between quotes
			start := strings.Index(line, "\"")
			end := strings.Index(line[start+1:], "\"")
			if start >= 0 && end > 0 {
				key := line[start+1 : start+1+end]
				// Check if key contains uppercase letter after lowercase (camelCase)
				for i := 1; i < len(key); i++ {
					if key[i] >= 'A' && key[i] <= 'Z' && key[i-1] >= 'a' && key[i-1] <= 'z' {
						return true
					}
				}
			}
		}
	}
	return false
}
