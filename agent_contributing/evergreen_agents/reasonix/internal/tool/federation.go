package tool

import "strings"

// ---------------------------------------------------------------------------
// Role-based tool sets (Evergreen multi-agent federation)
// ---------------------------------------------------------------------------

// RoleToolSet maps an agent role to its allowed tool names. Each role gets a
// scoped tool registry built from a base registry via RegistryForRole.
var RoleToolSets = map[string][]string{
	"planner": {
		"read_file", "code_index", "grep", "glob", "ls",
		"web_fetch", "code_search", "dependency_analyze", "experience_query",
	},
	"module_keeper": {
		"read_file", "code_index", "grep", "glob",
		"code_search", "dependency_analyze", "experience_query",
	},
	"task_executor": {
		"read_file", "write_file", "edit_file", "multi_edit",
		"delete_range", "delete_symbol", "move_file",
		"bash", "bash_output", "wait",
		"grep", "glob", "ls", "web_fetch", "todo",
		"code_index", "code_search",
		"dependency_analyze", "experience_query",
	},
	"inspector": {
		"read_file", "code_index", "grep", "glob", "ls",
		"code_search", "dependency_analyze", "experience_query",
	},
	"librarian": {
		"read_file", "grep", "glob",
		"experience_query",
	},
}

// RoleToolSet returns the allowed tool names for a role, or nil if unknown.
func RoleToolSet(role string) []string {
	return RoleToolSets[role]
}

// RegistryForRole builds a new Registry containing only the tools from base
// whose names are in the role's allow-list. If role is unknown, returns an
// empty registry. This is the Go equivalent of Python registry_for_role().
func RegistryForRole(role string, base *Registry) *Registry {
	allowed := RoleToolSets[role]
	if allowed == nil {
		return NewRegistry()
	}

	allowSet := make(map[string]bool, len(allowed))
	for _, name := range allowed {
		allowSet[name] = true
	}

	result := NewRegistry()
	base.mu.RLock()
	defer base.mu.RUnlock()

	for _, name := range base.order {
		if allowSet[name] {
			if t, ok := base.tools[name]; ok {
				result.Add(t)
			}
		}
		// Also allow MCP tools that match a prefix style
		if strings.HasPrefix(name, "mcp__") {
			result.Add(base.tools[name])
		}
	}

	return result
}
