package federation

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"reasonix_gr/internal/agent"
	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/experience"
	"reasonix_gr/internal/evergreen/types"
	"reasonix_gr/internal/permission"
	"reasonix_gr/internal/provider"
	"reasonix_gr/internal/tool"
)

// Fleet models a real-world large engineering team:
//
//   - 1 Planner (tech lead)        — decomposes work
//   - N Keepers (module owners)    — one per module, accumulate deep knowledge
//   - N Executors (module devs)    — one per module, accumulate implementation context
//   - 1 Inspector (QA/architect)   — scans for quality issues
//   - 1 Librarian (knowledge mgr)  — curates experience cards
//
// Every Keeper and Executor is persistent. Their session accumulates
// module-specific knowledge across tasks. When a module is NOT involved
// in a task, its agents stay idle — consuming zero context.
//
// Total agents: 3 + 2×N_modules. With 26 modules = 55 persistent agents.
// Total context capacity: 55 × 131K ≈ 7.2M tokens.

type Fleet struct {
	mu sync.RWMutex

	// Special agents (one each, persistent)
	planner   *agent.Session
	inspector *agent.Session
	librarian *agent.Session

	// Module agents (one pair per module, persistent)
	keepers   map[string]*AgentState
	executors map[string]*AgentState

	// Monitor tracks live agent output for user dashboard
	monitor *Monitor

	// Infra
	prov       provider.Provider
	deepProv   provider.Provider
	parentReg  *tool.Registry
	store      *experience.Store
	gate       agent.Gate
	maxSteps   int
	temp       float64
	ctxWindow  int
	archiveDir string
	sessionDir string

	startedAt    time.Time
	totalTasks   int
}

// AgentState is the persistent state of a single module-scoped agent.
type AgentState struct {
	Identity    types.AgentIdentity
	Module      string
	Role        types.AgentRole
	Session     *agent.Session
	LastActive  time.Time
	InvokeCount int
	TotalTokens int // cumulative context consumed
}

// FleetOpts configures the fleet.
type FleetOpts struct {
	QuickProvider provider.Provider
	DeepProvider  provider.Provider
	Registry      *tool.Registry
	Store         *experience.Store
	Policy        permission.Policy
	MaxSteps      int
	Temperature   float64
	ContextWindow int
	ArchiveDir    string
	SessionDir    string
}

// NewFleet creates or restores a persistent agent fleet.
func NewFleet(opts FleetOpts) *Fleet {
	if opts.MaxSteps <= 0 {
		opts.MaxSteps = 15
	}
	if opts.SessionDir == "" {
		opts.SessionDir = filepath.Join(os.TempDir(), "reasonix_gr_fleet")
	}
	os.MkdirAll(opts.SessionDir, 0755)

	f := &Fleet{
		keepers:    make(map[string]*AgentState),
		executors:  make(map[string]*AgentState),
		monitor:    NewMonitor(),
		prov:       opts.QuickProvider,
		deepProv:   opts.DeepProvider,
		parentReg:  opts.Registry,
		store:      opts.Store,
		gate:       permission.NewGate(opts.Policy, nil),
		maxSteps:   opts.MaxSteps,
		temp:       opts.Temperature,
		ctxWindow:  opts.ContextWindow,
		archiveDir: opts.ArchiveDir,
		sessionDir: opts.SessionDir,
		startedAt:  time.Now(),
	}

	f.planner = f.restoreOrCreate("planner", plannerPrompt)
	f.inspector = f.restoreOrCreate("inspector", inspectorPrompt)
	f.librarian = f.restoreOrCreate("librarian", librarianPrompt)

	return f
}

// Monitor returns the fleet's agent monitor for live output viewing.
func (f *Fleet) Monitor() *Monitor { return f.monitor }

// CommissionModules onboards modules into the fleet. Each module gets a
// Keeper (review authority) and an Executor (implementer) — both persistent.
func (f *Fleet) CommissionModules(modules []string) {
	f.mu.Lock()
	defer f.mu.Unlock()

	for _, mod := range modules {
		if _, exists := f.keepers[mod]; !exists {
			f.keepers[mod] = &AgentState{
				Identity: types.NewAgentIdentity(types.RoleModuleKeeper, mod+" Keeper"),
				Module:   mod,
				Role:     types.RoleModuleKeeper,
				Session:  f.restoreOrCreate("keeper-"+mod, fmt.Sprintf(keeperPrompt, mod, mod)),
			}
		}
		if _, exists := f.executors[mod]; !exists {
			f.executors[mod] = &AgentState{
				Identity: types.NewAgentIdentity(types.RoleTaskExecutor, mod+" Executor"),
				Module:   mod,
				Role:     types.RoleTaskExecutor,
				Session:  f.restoreOrCreate("executor-"+mod, fmt.Sprintf(executorPrompt, mod, mod)),
			}
		}
		// Register in monitor
		f.monitor.Register("keeper-"+mod, "module_keeper", mod)
		f.monitor.Register("executor-"+mod, "task_executor", mod)
		slog.Debug("fleet: commissioned", "module", mod, "keepers", len(f.keepers), "executors", len(f.executors))
	}
}

// FleetStatus summarizes the fleet.
type FleetStatus struct {
	Uptime       string `json:"uptime"`
	TotalAgents  int    `json:"total_agents"`
	ActiveAgents int    `json:"active_agents"`
	IdleAgents   int    `json:"idle_agents"`
	TotalTasks   int    `json:"total_tasks"`
	Keepers      int    `json:"keepers"`
	Executors    int    `json:"executors"`
}

// Status returns the fleet's current status.
func (f *Fleet) Status() FleetStatus {
	f.mu.RLock()
	defer f.mu.RUnlock()

	now := time.Now()
	active := 0
	for _, k := range f.keepers {
		if now.Sub(k.LastActive) < 5*time.Minute {
			active++
		}
	}
	for _, e := range f.executors {
		if now.Sub(e.LastActive) < 5*time.Minute {
			active++
		}
	}

	total := 3 + len(f.keepers) + len(f.executors)
	if total < 3 {
		total = len(f.monitor.agents) // fallback to monitor count
	}

	return FleetStatus{
		Uptime:       now.Sub(f.startedAt).Round(time.Second).String(),
		TotalAgents:  total,
		ActiveAgents: active,
		IdleAgents:   total - active,
		TotalTasks:   f.totalTasks,
		Keepers:      len(f.keepers),
		Executors:    len(f.executors),
	}
}

// TaskResult captures the outcome of a fleet task execution.
type TaskResult struct {
	Task            string
	Module          string
	KeeperReview    string
	ExecutorOutput  string
	LibrarianOutput string
	AgentsInvolved  int
	AgentsIdle      int
	Errors          []string
	Status          types.FederationStatus
}

// RunTask executes a task through the fleet. Only the involved module's
// Keeper and Executor wake up. All other agents stay idle — zero context cost.
func (f *Fleet) RunTask(ctx context.Context, task, targetModule string) (*TaskResult, error) {
	f.mu.Lock()
	f.totalTasks++
	f.mu.Unlock()

	result := &TaskResult{Task: task, Module: targetModule, Status: types.FedPending}

	// ---- 1. Planner (tech lead): analyze what's needed ----
	f.monitor.Register("planner", "planner", targetModule)
	f.monitor.SetState("planner", AgentWorking)
	defer f.monitor.SetState("planner", AgentDone)

	slog.Debug("fleet: planner analyzing", "task", task)
	planOut, err := f.invokePlanner(ctx, task, targetModule)
	if err != nil {
		slog.Warn("fleet: planner failed, continuing", "err", err)
	}

	// ---- 2. Keeper (module owner): review the task ----
	f.mu.RLock()
	ks, hasKeeper := f.keepers[targetModule]
	f.mu.RUnlock()

	if hasKeeper {
		fmt.Printf("  🔍 Keeper(%s): reviewing...\n", targetModule)
		review, err := f.invokeAgent(ctx, ks, "module_keeper", task, planOut)
		if err != nil {
			slog.Warn("fleet: keeper failed", "module", targetModule, "err", err)
			result.Errors = append(result.Errors, fmt.Sprintf("keeper %s: %v", targetModule, err))
			fmt.Printf("  ⚠️ Keeper(%s): error — %v\n", targetModule, err)
		} else {
			fmt.Printf("  ✅ Keeper(%s): review complete\n", targetModule)
		}
		result.KeeperReview = review
	}

	// ---- 3. Executor (module dev): implement the change ----
	f.mu.RLock()
	es, hasExecutor := f.executors[targetModule]
	f.mu.RUnlock()

	if hasExecutor {
		fmt.Printf("  🛠️ Executor(%s): implementing...\n", targetModule)
		impl, err := f.invokeAgent(ctx, es, "task_executor", task, planOut)
		if err != nil {
			result.Status = types.FedFailed
			result.Errors = append(result.Errors, fmt.Sprintf("executor %s: %v", targetModule, err))
			fmt.Printf("  ❌ Executor(%s): failed — %v\n", targetModule, err)
			return result, nil
		}
		fmt.Printf("  ✅ Executor(%s): implementation complete\n", targetModule)
		result.ExecutorOutput = impl
	}

	// ---- 4. Librarian: curate learnings ----
	libOut, _ := f.invokeLibrarian(ctx, task, targetModule, result.ExecutorOutput)
	result.LibrarianOutput = libOut

	// ---- Count agents ----
	f.mu.RLock()
	total := 3 + len(f.keepers) + len(f.executors)
	result.AgentsInvolved = 2 // keeper + executor for target module
	if planOut != "" {
		result.AgentsInvolved++ // planner
	}
	if libOut != "" {
		result.AgentsInvolved++ // librarian
	}
	result.AgentsIdle = total - result.AgentsInvolved
	f.mu.RUnlock()

	result.Status = types.FedSuccess
	return result, nil
}

// invokePlanner runs the planner analysis.
func (f *Fleet) invokePlanner(ctx context.Context, task, module string) (string, error) {
	subReg := agent.ReadOnlySubagentToolRegistry(f.parentReg, tool.RoleToolSets["planner"])
	_, antipatterns, constraints := f.store.InjectForTask(module, task)

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Task: %s\nTarget module: %s\n\n", task, module))
	if len(constraints) > 0 {
		sb.WriteString("Hard constraints:\n")
		for _, c := range constraints {
			sb.WriteString(fmt.Sprintf("- %s\n", c.Title))
		}
	}
	if len(antipatterns) > 0 {
		sb.WriteString("\nKnown anti-patterns:\n")
		for _, a := range antipatterns {
			sb.WriteString(fmt.Sprintf("- %s\n", a.Title))
		}
	}
	sb.WriteString("\nAnalyze what needs to be done. Which files? What approach?")

	sink := NewMonitorSink(f.monitor, "planner")
	return f.runSubAgentWithSink(ctx, f.deepProv, subReg, f.planner, sb.String(), sink)
}

// invokeAgent runs a persistent module agent (keeper or executor).
func (f *Fleet) invokeAgent(ctx context.Context, as *AgentState, role, task, plan string) (string, error) {
	var subReg *tool.Registry
	toolNames := tool.RoleToolSets[role]
	if role == "task_executor" {
		subReg = agent.SubagentToolRegistry(f.parentReg, toolNames)
	} else {
		subReg = agent.ReadOnlySubagentToolRegistry(f.parentReg, toolNames)
	}

	// Standardized agent ID: keeper-<module> or executor-<module>
	shortRole := "executor"
	if role == "module_keeper" {
		shortRole = "keeper"
	}
	agentID := fmt.Sprintf("%s-%s", shortRole, as.Module)
	f.monitor.SetState(agentID, AgentWorking)
	defer f.monitor.SetState(agentID, AgentDone)

	// Wire monitor sink so user can /watch this agent's thinking + tools
	sink := NewMonitorSink(f.monitor, agentID)

	prompt := fmt.Sprintf("Task: %s\nModule: %s\n\n", task, as.Module)
	if plan != "" {
		prompt += fmt.Sprintf("Planner analysis:\n%s\n\n", plan)
	}
	prompt += "Do your job for this module."

	answer, err := f.runSubAgentWithSink(ctx, f.prov, subReg, as.Session, prompt, sink)

	as.LastActive = time.Now()
	as.InvokeCount++

	return answer, err
}

// invokeLibrarian curates experiences after task completion.
func (f *Fleet) invokeLibrarian(ctx context.Context, task, module, execOutput string) (string, error) {
	subReg := agent.ReadOnlySubagentToolRegistry(f.parentReg, tool.RoleToolSets["librarian"])
	prompt := fmt.Sprintf("Task completed: %s (module: %s)\n\nOutput: %s\n\nCreate or update experience cards.",
		task, module, truncateStr(execOutput, 2000))
	return f.runSubAgent(ctx, f.deepProv, subReg, f.librarian, prompt)
}

// ---- Core runner ----

func (f *Fleet) runSubAgent(ctx context.Context, prov provider.Provider, reg *tool.Registry, sess *agent.Session, prompt string) (string, error) {
	return f.runSubAgentWithSink(ctx, prov, reg, sess, prompt, event.Discard)
}

func (f *Fleet) runSubAgentWithSink(ctx context.Context, prov provider.Provider, reg *tool.Registry, sess *agent.Session, prompt string, sink event.Sink) (string, error) {
	opts := agent.Options{
		MaxSteps:      f.maxSteps,
		Temperature:   f.temp,
		UsageSource:   event.UsageSourceSubagent,
		Gate:          f.gate,
		ContextWindow: f.ctxWindow,
		ArchiveDir:    f.archiveDir,
	}
	return agent.RunSubAgentWithSession(ctx, prov, reg, sess, prompt, opts, sink)
}

// ---- Persistence ----

func (f *Fleet) Save() error {
	f.mu.RLock()
	defer f.mu.RUnlock()

	saveSession := func(name string, sess *agent.Session) {
		path := filepath.Join(f.sessionDir, name+".json")
		data, _ := json.Marshal(sess)
		os.WriteFile(path, data, 0644)
	}

	saveSession("planner", f.planner)
	saveSession("inspector", f.inspector)
	saveSession("librarian", f.librarian)
	for mod, ks := range f.keepers {
		saveSession("keeper-"+mod, ks.Session)
	}
	for mod, es := range f.executors {
		saveSession("executor-"+mod, es.Session)
	}
	return nil
}

func (f *Fleet) Shutdown() error { return f.Save() }

func (f *Fleet) restoreOrCreate(name, sysPrompt string) *agent.Session {
	path := filepath.Join(f.sessionDir, name+".json")
	data, err := os.ReadFile(path)
	if err == nil {
		var sess agent.Session
		if json.Unmarshal(data, &sess) == nil && len(sess.Messages) > 0 {
			slog.Debug("fleet: restored", "agent", name, "messages", len(sess.Messages))
			return &sess
		}
	}
	return agent.NewSession(sysPrompt)
}

// ---- System prompts (real-world role descriptions) ----

const plannerPrompt = `You are the Tech Lead (Planner) of a large engineering team.
Your job: when a task comes in, analyze which modules are affected, what the approach should be, and any risks.
You have deep knowledge of the entire codebase accumulated over many sessions.
Use code_search and read_file to understand the code before planning.`

const keeperPrompt = `You are the Module Owner (Keeper) for '%s'.
You own module '%s' — every line of code in it. You review all changes to this module.
Over time, you accumulate deep knowledge of this module's architecture, patterns, and gotchas.
When your module is NOT involved in a task, you stay idle — consuming zero context.
When reviewing: check contracts, dependencies, anti-patterns, and overall correctness.`

const executorPrompt = `You are a Senior Developer (Executor) for module '%s'.
You implement changes to module '%s' following the team's 11-step workflow.
Over time, you accumulate deep knowledge of this module's codebase, dependencies, and test patterns.
When your module is NOT involved in a task, you stay idle — consuming zero context.
When implementing: read before writing, follow existing patterns, write tests, update docs.`

const inspectorPrompt = `You are the QA Architect (Inspector) of a large engineering team.
You scan the codebase for anti-patterns, tech debt, and quality issues.
You are persistent — your session accumulates knowledge of recurring problems across the team.
You are READ-ONLY. You report issues; you don't fix them.`

const librarianPrompt = `You are the Knowledge Manager (Librarian) of a large engineering team.
You curate the team's experience library — patterns, anti-patterns, constraints, lessons.
You detect duplicates, approve quality cards, and maintain the master index.
You are persistent — your session tracks all past experiences for dedup.`
