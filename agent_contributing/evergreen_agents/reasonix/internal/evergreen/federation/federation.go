// Package federation implements the multi-agent orchestration engine for the
// Evergreen federation. It manages shared state, the workflow graph (Planner →
// Contract → Keepers → Executors → Review → MergeQueue), and conditional
// routing logic (debate loops, contract re-negotiation, error budget checks,
// escalation paths).
//
// Ported from src/graph/state.py + workflow.py + conditional.py.
package federation

import (
	"reasonix_gr/internal/evergreen/types"
)

// Workflow orchestrates a federation run: Planner → Contract → Keepers →
// Executors → Review → MergeQueue.
type Workflow struct {
	state      *types.AgentFederationState
	nodes      map[string]NodeFunc
	edges      map[string][]string // node → next nodes
	conditions map[string]ConditionFunc
}

// NodeFunc is a function executed at a workflow node. It receives the shared
// state and returns the next node name (or "" to follow default edges).
type NodeFunc func(state *types.AgentFederationState) (string, error)

// ConditionFunc decides which edge to follow from a node. Returns the next
// node name or "" to end.
type ConditionFunc func(state *types.AgentFederationState) string

// NewWorkflow creates an empty federation workflow.
func NewWorkflow() *Workflow {
	return &Workflow{
		state:      nil,
		nodes:      make(map[string]NodeFunc),
		edges:      make(map[string][]string),
		conditions: make(map[string]ConditionFunc),
	}
}

// SetState sets the shared federation state.
func (w *Workflow) SetState(state *types.AgentFederationState) {
	w.state = state
}

// State returns the current federation state.
func (w *Workflow) State() *types.AgentFederationState {
	return w.state
}

// AddNode registers a node function.
func (w *Workflow) AddNode(name string, fn NodeFunc) {
	w.nodes[name] = fn
}

// AddEdge registers a directed edge between nodes.
func (w *Workflow) AddEdge(from, to string) {
	w.edges[from] = append(w.edges[from], to)
}

// AddCondition registers a conditional routing function for a node.
func (w *Workflow) AddCondition(node string, fn ConditionFunc) {
	w.conditions[node] = fn
}

// Run executes the workflow starting from the given node.
// It iterates: execute node → check condition → follow edge or condition → repeat.
func (w *Workflow) Run(startNode string) error {
	current := startNode
	visited := make(map[string]bool)

	for current != "" {
		if visited[current] {
			// Cycle detected — stop
			break
		}
		visited[current] = true

		fn, ok := w.nodes[current]
		if !ok {
			break
		}

		next, err := fn(w.state)
		if err != nil {
			w.state.FinalStatus = types.FedFailed
			return err
		}

		// Check explicit next from node function
		if next != "" {
			current = next
			continue
		}

		// Check conditional routing
		if cond, ok := w.conditions[current]; ok {
			if chosen := cond(w.state); chosen != "" {
				current = chosen
				continue
			}
		}

		// Follow default edge
		if nexts, ok := w.edges[current]; ok && len(nexts) > 0 {
			current = nexts[0]
		} else {
			current = "" // end
		}
	}

	if w.state.FinalStatus == types.FedPending {
		w.state.FinalStatus = types.FedSuccess
	}
	return nil
}

// ---------------------------------------------------------------------------
// Conditional Logic (port of conditional.py)
// ---------------------------------------------------------------------------

// ConditionalLogic provides routing decisions for the federation workflow.
type ConditionalLogic struct {
	MaxDebateRounds int
	ErrorBudgetLimit float64
}

// NewConditionalLogic creates a conditional logic engine with defaults.
func NewConditionalLogic() *ConditionalLogic {
	return &ConditionalLogic{
		MaxDebateRounds: 3,
		ErrorBudgetLimit: 100.0,
	}
}

// AfterPlanner decides the next step after planning completes.
func (c *ConditionalLogic) AfterPlanner(state *types.AgentFederationState) string {
	if state.TaskTree == nil || len(state.TaskTree.Nodes) == 0 {
		return "" // no tasks, end
	}
	if len(state.TaskTree.Contracts) > 0 && len(state.ActiveContracts) == 0 {
		return "contract_validation" // contracts need approval
	}
	return "module_keepers" // go straight to execution
}

// AfterContractValidation decides after contract phase.
func (c *ConditionalLogic) AfterContractValidation(state *types.AgentFederationState) string {
	allAccepted := true
	for _, ct := range state.ActiveContracts {
		if ct.Status != types.ContractAccepted {
			allAccepted = false
			break
		}
	}
	if !allAccepted {
		return "" // blocked — contracts must be resolved
	}
	return "module_keepers"
}

// ShouldContinueDebate checks whether another debate round is warranted.
func (c *ConditionalLogic) ShouldContinueDebate(state *types.AgentFederationState) bool {
	if state.DebateState == nil {
		return false
	}
	if state.DebateState.Resolved {
		return false
	}
	return state.DebateState.Round < state.DebateState.MaxRounds
}

// AfterReview decides post-review routing.
func (c *ConditionalLogic) AfterReview(state *types.AgentFederationState) string {
	// Check for failed nodes that need rework
	if len(state.FailedNodes) > 0 {
		return "task_executors" // re-execute failed tasks
	}
	// Check if all tasks are done
	allDone := true
	for _, node := range state.TaskTree.Nodes {
		if !node.Status.IsTerminal() {
			allDone = false
			break
		}
	}
	if allDone {
		return "merge_queue"
	}
	return "task_executors"
}

// CheckErrorBudget decides whether the error budget allows continuation.
func (c *ConditionalLogic) CheckErrorBudget(state *types.AgentFederationState) bool {
	return state.ErrorBudgetConsumed < c.ErrorBudgetLimit
}

// ShouldEscalate decides whether to escalate to human review.
func (c *ConditionalLogic) ShouldEscalate(state *types.AgentFederationState) bool {
	// Escalate if error budget nearly exhausted
	if state.ErrorBudgetConsumed >= c.ErrorBudgetLimit*0.8 {
		return true
	}
	// Escalate if debate unresolved after max rounds
	if state.DebateState != nil && !state.DebateState.Resolved &&
		state.DebateState.Round >= state.DebateState.MaxRounds {
		return true
	}
	// Escalate if all tasks failed
	if len(state.CompletedNodes) == 0 && len(state.FailedNodes) > 0 {
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Standard workflow builder
// ---------------------------------------------------------------------------

// StandardPhases returns the canonical federation workflow phases in order.
func StandardPhases() []string {
	return []string{
		"planner",
		"contract_validation",
		"module_keepers",
		"task_executors",
		"keeper_reviews",
		"merge_queue",
	}
}

// BuildStandardWorkflow creates a workflow with the standard 6-phase pipeline
// and conditional routing. Node functions must be registered separately.
func BuildStandardWorkflow() *Workflow {
	w := NewWorkflow()

	// Standard edges
	w.AddEdge("planner", "contract_validation")
	w.AddEdge("contract_validation", "module_keepers")
	w.AddEdge("module_keepers", "task_executors")
	w.AddEdge("task_executors", "keeper_reviews")
	w.AddEdge("keeper_reviews", "merge_queue")

	// Conditional routing at key decision points
	cl := NewConditionalLogic()
	w.AddCondition("planner", cl.AfterPlanner)
	w.AddCondition("contract_validation", cl.AfterContractValidation)
	w.AddCondition("keeper_reviews", cl.AfterReview)

	return w
}
