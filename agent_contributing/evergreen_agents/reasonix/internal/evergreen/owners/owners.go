// Package owners manages the bi-directional module↔agent OWNERS mapping in the
// Evergreen federation. Each module has one or more Keeper agents; each agent
// may own one module.
//
// Ported from src/governance/owners.py.
package owners

import (
	"sync"
)

// Registry is a bi-directional mapping between modules and their Keeper agents.
type Registry struct {
	mu              sync.RWMutex
	agentToModule   map[string]string   // agentID → module
	moduleToAgents  map[string][]string // module → agentIDs
}

// NewRegistry creates an empty owners registry.
func NewRegistry() *Registry {
	return &Registry{
		agentToModule:  make(map[string]string),
		moduleToAgents: make(map[string][]string),
	}
}

// Register assigns an agent as a Keeper for a module. An agent can only own
// one module at a time; re-registering moves them.
func (r *Registry) Register(agentID, module string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Remove from previous module
	if prev, ok := r.agentToModule[agentID]; ok {
		r.moduleToAgents[prev] = removeStr(r.moduleToAgents[prev], agentID)
	}

	r.agentToModule[agentID] = module
	r.moduleToAgents[module] = appendUnique(r.moduleToAgents[module], agentID)
}

// Remove unregisters an agent from the OWNERS system.
func (r *Registry) Remove(agentID string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	module, ok := r.agentToModule[agentID]
	if !ok {
		return
	}

	delete(r.agentToModule, agentID)
	r.moduleToAgents[module] = removeStr(r.moduleToAgents[module], agentID)
}

// OwnersOf returns the Keeper agent IDs for a module.
func (r *Registry) OwnersOf(module string) []string {
	r.mu.RLock()
	defer r.mu.RUnlock()

	agents := r.moduleToAgents[module]
	out := make([]string, len(agents))
	copy(out, agents)
	return out
}

// ModulesOwnedBy returns the modules an agent is a Keeper for.
func (r *Registry) ModulesOwnedBy(agentID string) []string {
	r.mu.RLock()
	defer r.mu.RUnlock()

	module, ok := r.agentToModule[agentID]
	if !ok {
		return nil
	}
	return []string{module}
}

// IsOwner checks whether an agent is a registered Keeper for the given module.
func (r *Registry) IsOwner(agentID, module string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()

	m, ok := r.agentToModule[agentID]
	return ok && m == module
}

// RequireOwnerApproval checks whether at least one registered Keeper has
// approved. The approval set maps agentID → true.
func (r *Registry) RequireOwnerApproval(module string, approvals map[string]bool) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()

	keepers := r.moduleToAgents[module]
	for _, k := range keepers {
		if approvals[k] {
			return true
		}
	}
	return len(keepers) == 0 // no keepers = auto-approve
}

// Module returns the module owned by an agent, empty if none.
func (r *Registry) Module(agentID string) string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.agentToModule[agentID]
}

func appendUnique(slice []string, s string) []string {
	for _, v := range slice {
		if v == s {
			return slice
		}
	}
	return append(slice, s)
}

func removeStr(slice []string, s string) []string {
	for i, v := range slice {
		if v == s {
			return append(slice[:i], slice[i+1:]...)
		}
	}
	return slice
}
