// Package contracts manages interface contracts between modules in the Evergreen
// federation. Contracts define API boundaries and are approved by both the
// providing and consuming module's Keeper.
//
// Ported from src/contracts/model.py + proposal.py + validator.py.
package contracts

import (
	"sync"

	"reasonix_gr/internal/evergreen/types"
)

// Model manages the contract lifecycle: propose → approve (dual) → reject.
type Model struct {
	mu        sync.RWMutex
	contracts map[string]*types.Contract
}

// NewModel creates a contract model.
func NewModel() *Model {
	return &Model{
		contracts: make(map[string]*types.Contract),
	}
}

// Propose creates a new contract in PROPOSED status.
func (m *Model) Propose(fromModule, toModule, title, description string, spec map[string]interface{}, proposedBy string) *types.Contract {
	c := types.NewContract(fromModule, toModule, title, description, spec)
	c.ProposedBy = proposedBy

	m.mu.Lock()
	m.contracts[c.ContractID] = &c
	m.mu.Unlock()
	return &c
}

// Approve records one side's approval. Returns true when both sides have approved.
func (m *Model) Approve(contractID, module, agentID string) (*types.Contract, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	c := m.contracts[contractID]
	if c == nil {
		return nil, false
	}
	if c.Status != types.ContractProposed {
		return c, false
	}

	c.ApprovedBy[module] = agentID

	// Both sides approved?
	if c.ApprovedBy[c.FromModule] != "" && c.ApprovedBy[c.ToModule] != "" {
		c.Status = types.ContractAccepted
		return c, true
	}
	return c, false
}

// Reject rejects a contract.
func (m *Model) Reject(contractID, rejectedBy string) *types.Contract {
	m.mu.Lock()
	defer m.mu.Unlock()

	c := m.contracts[contractID]
	if c == nil {
		return nil
	}
	c.Status = types.ContractRejected
	return c
}

// Supersede marks a contract as superseded by a newer one.
func (m *Model) Supersede(contractID, supersededBy string) *types.Contract {
	m.mu.Lock()
	defer m.mu.Unlock()

	c := m.contracts[contractID]
	if c == nil {
		return nil
	}
	c.Status = types.ContractSuperseded
	c.SupersededBy = supersededBy
	return c
}

// Get returns a contract by ID.
func (m *Model) Get(contractID string) *types.Contract {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.contracts[contractID]
}

// ForModule returns all contracts involving the given module.
func (m *Model) ForModule(module string) []*types.Contract {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var out []*types.Contract
	for _, c := range m.contracts {
		if c.FromModule == module || c.ToModule == module {
			out = append(out, c)
		}
	}
	return out
}

// ActiveForModule returns only accepted contracts involving the module.
func (m *Model) ActiveForModule(module string) []*types.Contract {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var out []*types.Contract
	for _, c := range m.contracts {
		if c.Status == types.ContractAccepted && (c.FromModule == module || c.ToModule == module) {
			out = append(out, c)
		}
	}
	return out
}

// ListAll returns all contracts.
func (m *Model) ListAll() []*types.Contract {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := make([]*types.Contract, 0, len(m.contracts))
	for _, c := range m.contracts {
		out = append(out, c)
	}
	return out
}

// Count returns the total number of contracts.
func (m *Model) Count() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.contracts)
}

// ---------------------------------------------------------------------------
// Contract Validator
// ---------------------------------------------------------------------------

// Violation describes a contract violation found during code review.
type Violation struct {
	ContractID string `json:"contract_id"`
	FromModule string `json:"from_module"`
	ToModule   string `json:"to_module"`
	File       string `json:"file"`
	Message    string `json:"message"`
	Severity   string `json:"severity"`
}

// Validator checks code changes against active contracts.
type Validator struct {
	model *Model
}

// NewValidator creates a validator backed by the given model.
func NewValidator(model *Model) *Validator {
	return &Validator{model: model}
}

// ValidateChange checks whether a set of changed files and imports violates any
// active contract. Returns a list of violations found.
//
// In production, this would use AST parsing to extract actual imports. The
// current implementation performs simple string-based checks.
func (v *Validator) ValidateChange(module string, changedFiles []string, imports []string) []Violation {
	active := v.model.ActiveForModule(module)

	var violations []Violation
	for _, c := range active {
		// Validate imports: if from_module imports to_module's public API
		if c.FromModule == module {
			for _, imp := range imports {
				// Check if import uses the contract-specified interface
				if spec, ok := c.InterfaceSpec["allowed_imports"]; ok {
					if allowed, ok := spec.([]interface{}); ok {
						found := false
						for _, a := range allowed {
							if aStr, ok := a.(string); ok && aStr == imp {
								found = true
								break
							}
						}
						if !found {
							for _, f := range changedFiles {
								violations = append(violations, Violation{
									ContractID: c.ContractID,
									FromModule: c.FromModule,
									ToModule:   c.ToModule,
									File:       f,
									Message:    "import " + imp + " not in contract " + c.ContractID,
									Severity:   "warning",
								})
							}
						}
					}
				}
			}
		}
	}

	return violations
}

// VerifyAll runs validation for all modules with active contracts.
func (v *Validator) VerifyAll(moduleChanges map[string][]string) map[string][]Violation {
	result := make(map[string][]Violation)
	for module, files := range moduleChanges {
		violations := v.ValidateChange(module, files, nil)
		if len(violations) > 0 {
			result[module] = violations
		}
	}
	return result
}

// ProposalManager handles the draft → propose → approve flow for contracts.
type ProposalManager struct {
	model *Model
}

// NewProposalManager creates a proposal manager.
func NewProposalManager(model *Model) *ProposalManager {
	return &ProposalManager{model: model}
}

// Draft creates a proposed contract and returns it.
func (pm *ProposalManager) Draft(fromModule, toModule, title, description string, spec map[string]interface{}, proposedBy string) *types.Contract {
	return pm.model.Propose(fromModule, toModule, title, description, spec, proposedBy)
}

// Propose is an alias for Draft.
func (pm *ProposalManager) Propose(fromModule, toModule, title, description string, spec map[string]interface{}, proposedBy string) *types.Contract {
	return pm.Draft(fromModule, toModule, title, description, spec, proposedBy)
}

// Approve records one side's approval. Returns whether fully approved.
func (pm *ProposalManager) Approve(contractID, module, agentID string) (*types.Contract, bool) {
	return pm.model.Approve(contractID, module, agentID)
}

// IsFullyApproved checks if both sides have approved.
func (pm *ProposalManager) IsFullyApproved(contractID string) bool {
	c := pm.model.Get(contractID)
	if c == nil {
		return false
	}
	return c.ApprovedBy[c.FromModule] != "" && c.ApprovedBy[c.ToModule] != ""
}
