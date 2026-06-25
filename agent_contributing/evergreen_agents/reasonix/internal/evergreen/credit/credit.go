// Package credit provides the credit scoring engine and oversight for the
// Evergreen multi-agent federation. Each agent has a 6-dimensional credit score
// that governs task eligibility and review requirements.
//
// Ported from src/core/credit.py + src/governance/credit_oversight.py.
package credit

import (
	"sync"
	"time"

	"reasonix_gr/internal/evergreen/types"
)

// DefaultWeights maps each credit dimension to its default weight.
// Mirrors Python DEFAULT_WEIGHTS.
var DefaultWeights = map[string]float64{
	"code_quality":         0.25,
	"test_quality":         0.20,
	"review_accuracy":      0.20,
	"experience_quality":   0.15,
	"error_budget_respect": 0.10,
	"collaboration":        0.10,
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// Engine manages credit scores for all agents in the federation.
// Thread-safe via sync.RWMutex.
type Engine struct {
	mu      sync.RWMutex
	scores  map[string]*types.CreditScore
	weights map[string]float64
}

// NewEngine creates a credit engine with default weights.
func NewEngine(weights map[string]float64) *Engine {
	if weights == nil {
		weights = DefaultWeights
	}
	return &Engine{
		scores:  make(map[string]*types.CreditScore),
		weights: weights,
	}
}

// Register adds a new agent with default scores. Returns the created score.
func (e *Engine) Register(agentID string, role types.AgentRole) *types.CreditScore {
	e.mu.Lock()
	defer e.mu.Unlock()

	cs := types.NewCreditScore(agentID, role)
	e.scores[agentID] = &cs
	return &cs
}

// Get returns an agent's credit score, or nil if not found.
func (e *Engine) Get(agentID string) *types.CreditScore {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.scores[agentID]
}

// ListAll returns all credit scores.
func (e *Engine) ListAll() []*types.CreditScore {
	e.mu.RLock()
	defer e.mu.RUnlock()

	out := make([]*types.CreditScore, 0, len(e.scores))
	for _, cs := range e.scores {
		out = append(out, cs)
	}
	return out
}

// ApplyDelta adjusts one dimension of an agent's credit score.
// Positive = improvement, negative = degradation.
func (e *Engine) ApplyDelta(agentID, dimension string, delta float64) *types.CreditScore {
	e.mu.Lock()
	defer e.mu.Unlock()

	cs := e.scores[agentID]
	if cs == nil {
		return nil
	}

	current := dimensionValue(cs, dimension)
	if current == nil {
		return nil
	}

	*current = clamp(*current+delta, 0.0, 100.0)
	e.recomputeComposite(cs)
	now := time.Now()
	cs.LastEvaluated = &now
	return cs
}

// OnTaskCompleted applies typical task-completion deltas.
func (e *Engine) OnTaskCompleted(agentID string, success, lintPass bool, testCoverage float64, reviewApproved bool) *types.CreditScore {
	e.mu.Lock()
	defer e.mu.Unlock()

	cs := e.scores[agentID]
	if cs == nil {
		return nil
	}

	cs.TotalTasks++

	if success {
		if lintPass {
			e.applyDeltaLocked(cs, "code_quality", 2.0)
		} else {
			e.applyDeltaLocked(cs, "code_quality", -5.0)
		}
		if testCoverage >= 0.8 {
			e.applyDeltaLocked(cs, "test_quality", 5.0)
		} else {
			e.applyDeltaLocked(cs, "test_quality", -3.0)
		}
	} else {
		e.applyDeltaLocked(cs, "code_quality", -10.0)
		e.applyDeltaLocked(cs, "test_quality", -5.0)
	}

	if reviewApproved {
		cs.TotalApprovals++
	} else {
		cs.TotalRejections++
	}

	now := time.Now()
	cs.LastEvaluated = &now
	e.recomputeComposite(cs)
	return cs
}

// OnReviewResult adjusts review accuracy when a review by this agent is validated.
func (e *Engine) OnReviewResult(agentID string, wasCorrect bool) *types.CreditScore {
	delta := -8.0
	if wasCorrect {
		delta = 3.0
	}
	return e.ApplyDelta(agentID, "review_accuracy", delta)
}

// OnExperienceApproved adjusts experience quality when an experience card is approved.
func (e *Engine) OnExperienceApproved(agentID string, useful bool) *types.CreditScore {
	delta := -2.0
	if useful {
		delta = 5.0
	}
	return e.ApplyDelta(agentID, "experience_quality", delta)
}

// OnErrorBudgetBust applies a penalty when an agent's module exceeds error budget.
func (e *Engine) OnErrorBudgetBust(agentID string, amount float64) *types.CreditScore {
	return e.ApplyDelta(agentID, "error_budget_respect", -amount)
}

// CanExecute checks if an agent meets the minimum credit threshold.
func (e *Engine) CanExecute(agentID string, minScore float64) bool {
	e.mu.RLock()
	defer e.mu.RUnlock()

	cs := e.scores[agentID]
	return cs != nil && cs.Composite >= minScore
}

// LowestScoring returns the n lowest-scoring agents.
func (e *Engine) LowestScoring(n int) []*types.CreditScore {
	e.mu.RLock()
	defer e.mu.RUnlock()

	all := make([]*types.CreditScore, 0, len(e.scores))
	for _, cs := range e.scores {
		all = append(all, cs)
	}

	// Simple insertion sort by composite score ascending
	for i := 1; i < len(all); i++ {
		j := i
		for j > 0 && all[j].Composite < all[j-1].Composite {
			all[j], all[j-1] = all[j-1], all[j]
			j--
		}
	}

	if n > len(all) {
		n = len(all)
	}
	return all[:n]
}

// ---------------------------------------------------------------------------
// Internal helpers (must hold mu)
// ---------------------------------------------------------------------------

func (e *Engine) applyDeltaLocked(cs *types.CreditScore, dimension string, delta float64) {
	current := dimensionValue(cs, dimension)
	if current == nil {
		return
	}
	*current = clamp(*current+delta, 0.0, 100.0)
}

func (e *Engine) recomputeComposite(cs *types.CreditScore) {
	composite := cs.CodeQuality*e.weights["code_quality"] +
		cs.TestQuality*e.weights["test_quality"] +
		cs.ReviewAccuracy*e.weights["review_accuracy"] +
		cs.ExperienceQuality*e.weights["experience_quality"] +
		cs.ErrorBudgetRespect*e.weights["error_budget_respect"] +
		cs.Collaboration*e.weights["collaboration"]
	cs.Composite = clamp(composite, 0.0, 100.0)
}

func dimensionValue(cs *types.CreditScore, dim string) *float64 {
	switch dim {
	case "code_quality":
		return &cs.CodeQuality
	case "test_quality":
		return &cs.TestQuality
	case "review_accuracy":
		return &cs.ReviewAccuracy
	case "experience_quality":
		return &cs.ExperienceQuality
	case "error_budget_respect":
		return &cs.ErrorBudgetRespect
	case "collaboration":
		return &cs.Collaboration
	default:
		return nil
	}
}
