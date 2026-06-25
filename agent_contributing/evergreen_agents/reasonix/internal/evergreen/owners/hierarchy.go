package owners

import (
	"fmt"
	"path/filepath"
	"strings"
	"sync"
)

// Hierarchy implements hierarchical OWNERS — the root→leaf responsibility chain.
//
// Root OWNERS protect global architecture; leaf OWNERS own business logic.
// An MR must get approval from ALL levels it touches, not just the leaf.
//
//	root/                          ← root OWNERS (global architecture)
//	  lib/features/auth/            ← auth OWNERS (login, session)
//	    lib/features/auth/widgets/  ← widget OWNERS (UI components)

// Hierarchy extends the flat Registry with directory-level ownership.
type Hierarchy struct {
	mu    sync.RWMutex
	flat  *Registry      // module-level mapping (existing)
	nodes map[string]*OwnersNode // directory → owners
}

// OwnersNode is one directory in the ownership tree.
type OwnersNode struct {
	Path    string   // directory path relative to repo root
	Owners  []string // agent_ids with OWNERS authority
	Parent  *OwnersNode
	Children []*OwnersNode
	Level   int      // 0 = root, deeper = more specific
}

// ApprovalLevel tracks which level approved a change.
type ApprovalLevel struct {
	Path     string // directory path
	Level    int    // hierarchy depth
	Owner    string // who approved
	Approved bool
}

// NewHierarchy creates a hierarchical owners structure from a flat registry
// and module paths.
func NewHierarchy(flat *Registry) *Hierarchy {
	return &Hierarchy{
		flat:  flat,
		nodes: make(map[string]*OwnersNode),
	}
}

// AddDirectory registers owners for a directory path. Parent directories
// are auto-created if they don't exist.
func (h *Hierarchy) AddDirectory(path string, owners []string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	// Normalize path
	path = filepath.ToSlash(filepath.Clean(path))
	if path == "." {
		path = ""
	}

	// Create or update node
	node, exists := h.nodes[path]
	if !exists {
		node = &OwnersNode{Path: path, Owners: owners, Level: h.depthLevel(path)}
		h.nodes[path] = node
	} else {
		node.Owners = owners
	}

	// Link to parent
	if path != "" {
		parentPath := filepath.ToSlash(filepath.Dir(path))
		if parentPath == "." {
			parentPath = ""
		}
		parent, parentExists := h.nodes[parentPath]
		if !parentExists {
			parent = &OwnersNode{Path: parentPath, Level: h.depthLevel(parentPath)}
			h.nodes[parentPath] = parent
		}
		node.Parent = parent
		parent.Children = append(parent.Children, node)
	}
}

// ValidateChange checks whether changed files have been approved at ALL levels.
// Returns the list of levels that still need approval.
func (h *Hierarchy) ValidateChange(changedFiles []string, approvals map[string]string) ([]ApprovalLevel, bool) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	// Collect all affected directory levels
	affected := make(map[string]*OwnersNode)
	for _, file := range changedFiles {
		dir := filepath.ToSlash(filepath.Dir(file))
		// Walk up the directory tree
		for dir != "." && dir != "" {
			if node, ok := h.nodes[dir]; ok {
				affected[dir] = node
			}
			parent := filepath.ToSlash(filepath.Dir(dir))
			if parent == dir {
				break
			}
			dir = parent
		}
		// Root level
		if node, ok := h.nodes[""]; ok {
			affected[""] = node
		}
	}

	// Check each level
	var pending []ApprovalLevel
	allApproved := true

	for path, node := range affected {
		approved := false
		approver := ""
		for _, owner := range node.Owners {
			if a, ok := approvals[path]; ok && a == owner {
				approved = true
				approver = owner
				break
			}
		}
		if !approved && len(node.Owners) > 0 {
			allApproved = false
		}
		pending = append(pending, ApprovalLevel{
			Path:     path,
			Level:    node.Level,
			Owner:    approver,
			Approved: approved,
		})
	}

	return pending, allApproved
}

// GenerateOwnersFile generates the content for an OWNERS file at a given path.
func (h *Hierarchy) GenerateOwnersFile(path string) string {
	h.mu.RLock()
	defer h.mu.RUnlock()

	node, ok := h.nodes[path]
	if !ok || len(node.Owners) == 0 {
		return ""
	}

	var b strings.Builder
	b.WriteString(fmt.Sprintf("# OWNERS — %s\n", orPath(path, "root")))
	b.WriteString("# Auto-generated. Each line is an agent_id with approval authority.\n")
	b.WriteString("# Changes to files in this directory require at least one owner's approval.\n")
	b.WriteString("# Parent OWNERS also apply — see root OWNERS for global policies.\n\n")

	for _, owner := range node.Owners {
		b.WriteString(owner + "\n")
	}

	if node.Parent != nil {
		b.WriteString(fmt.Sprintf("\n# Parent: %s\n", orPath(node.Parent.Path, "root")))
	}

	return b.String()
}

// depthLevel returns the hierarchy depth of a path.
func (h *Hierarchy) depthLevel(path string) int {
	if path == "" {
		return 0 // root
	}
	return strings.Count(path, "/") + 1
}

func orPath(p, fallback string) string {
	if p == "" {
		return fallback
	}
	return p
}
