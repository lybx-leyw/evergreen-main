package federation

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"strings"

	"reasonix_gr/internal/agent"
	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/experience"
	"reasonix_gr/internal/evergreen/types"
	"reasonix_gr/internal/permission"
	"reasonix_gr/internal/provider"
	"reasonix_gr/internal/tool"
)

// Orchestrator runs the federation workflow with real sub-agents. Each phase
// (planner, keeper, executor, inspector, librarian) spawns an isolated
// sub-agent via RunSubAgentWithSession with its own session, scoped tools,
// and event stream.
type Orchestrator struct {
	prov          provider.Provider // quick-thinking provider
	deepProv      provider.Provider // deep-thinking provider
	parentReg     *tool.Registry
	sink          event.Sink
	store         *experience.Store
	headlessGate  agent.Gate
	maxSteps      int
	temperature   float64
	ctxWindow     int
	archiveDir    string
}

// OrchestratorOpts holds configuration for the orchestrator.
type OrchestratorOpts struct {
	QuickProvider  provider.Provider
	DeepProvider   provider.Provider
	Registry       *tool.Registry
	Sink           event.Sink
	Store          *experience.Store
	Policy         permission.Policy
	MaxSteps       int
	Temperature    float64
	ContextWindow  int
	ArchiveDir     string
}

// NewOrchestrator creates a federation orchestrator.
func NewOrchestrator(opts OrchestratorOpts) *Orchestrator {
	if opts.MaxSteps <= 0 {
		opts.MaxSteps = 15
	}
	if opts.Temperature <= 0 {
		opts.Temperature = 0.3
	}
	if opts.Sink == nil {
		opts.Sink = event.Discard
	}
	return &Orchestrator{
		prov:         opts.QuickProvider,
		deepProv:     opts.DeepProvider,
		parentReg:    opts.Registry,
		sink:         opts.Sink,
		store:        opts.Store,
		headlessGate: permission.NewGate(opts.Policy, nil),
		maxSteps:     opts.MaxSteps,
		temperature:  opts.Temperature,
		ctxWindow:    opts.ContextWindow,
		archiveDir:   opts.ArchiveDir,
	}
}

// RunResult holds the output of a federation run.
type RunResult struct {
	PlannerOutput   string
	KeeperReviews   []string
	ExecutorOutputs []string
	InspectorReport string
	LibrarianOutput string
	Status          types.FederationStatus
}

// Run executes the full federation pipeline with parallel agents:
// Planner → [Keeper × N parallel] → [Executor × M parallel] → Inspector → Librarian.
//
// If modules is empty, only the target module's keeper runs.
// Otherwise, keepers run in parallel for every module in the list.
func (o *Orchestrator) Run(ctx context.Context, task, targetModule string, allModules []string, maxParallel int) (*RunResult, error) {
	if maxParallel <= 0 {
		maxParallel = 5 // default: 5 concurrent sub-agents
	}
	result := &RunResult{Status: types.FedPending}

	allMods := append([]string{targetModule}, allModules...)

	o.sink.Emit(event.Event{Kind: event.FederationStarted,
		Federation: &event.FederationPayload{
			System: &event.FederationSystem{RootTask: task, Modules: allMods},
		},
	})

	// ---- Phase 1: Planner (Deep-thinking, read-only) ----
	slog.Info("federation: planning", "task", task, "module", targetModule)
	planOutput, err := o.runPlanner(ctx, task, targetModule)
	if err != nil {
		result.Status = types.FedFailed
		return result, fmt.Errorf("planner: %w", err)
	}
	result.PlannerOutput = planOutput

	// ---- Phase 2: Keepers — PARALLEL across all modules ----
	slog.Info("federation: parallel keeper review", "modules", len(allMods))
	keeperResults := o.runKeepersParallel(ctx, task, planOutput, allMods, maxParallel)
	for _, kr := range keeperResults {
		result.KeeperReviews = append(result.KeeperReviews, kr.output)
		if kr.err != nil {
			slog.Warn("federation: keeper failed", "module", kr.module, "err", kr.err)
		}
		o.sink.Emit(event.Event{Kind: event.ReviewSubmitted,
			Federation: &event.FederationPayload{
				Review: &event.FederationReview{TaskID: task, Module: kr.module, Approved: kr.err == nil},
			},
		})
	}

	// ---- Phase 3: Executors — PARALLEL across sub-tasks ----
	// Decompose into sub-tasks (simple heuristic: one per involved module)
	subTasks := o.decomposeTask(task, allMods)
	slog.Info("federation: parallel execution", "subtasks", len(subTasks))
	execResults := o.runExecutorsParallel(ctx, planOutput, subTasks, maxParallel)
	for _, er := range execResults {
		result.ExecutorOutputs = append(result.ExecutorOutputs, er.output)
		if er.err != nil {
			slog.Warn("federation: executor failed", "module", er.module, "err", er.err)
		}
	}

	// ---- Phase 4: Inspector (Quick-thinking, read-only) ----
	slog.Info("federation: inspecting", "target", targetModule)
	inspectorOutput, err := o.runInspector(ctx, targetModule)
	if err != nil {
		slog.Warn("federation: inspector failed, continuing", "err", err)
	}
	result.InspectorReport = inspectorOutput

	// ---- Phase 5: Librarian (Deep-thinking) ----
	slog.Info("federation: curating", "task", task)
	librarianOutput, err := o.runLibrarian(ctx, task, targetModule, "")
	if err != nil {
		slog.Warn("federation: librarian failed, continuing", "err", err)
	}
	result.LibrarianOutput = librarianOutput

	result.Status = types.FedSuccess
	o.sink.Emit(event.Event{Kind: event.FederationCompleted,
		Federation: &event.FederationPayload{
			System: &event.FederationSystem{RootTask: task, Modules: allMods},
		},
	})

	return result, nil
}

// ---- Parallel execution helpers ----

type agentResult struct {
	module string
	output string
	err    error
}

// runKeepersParallel runs a Keeper sub-agent for each module in parallel.
func (o *Orchestrator) runKeepersParallel(ctx context.Context, task, planOutput string, modules []string, maxParallel int) []agentResult {
	return runParallel(modules, maxParallel, func(mod string) agentResult {
		out, err := o.runKeeper(ctx, task, mod, planOutput)
		return agentResult{module: mod, output: out, err: err}
	})
}

// runExecutorsParallel runs an Executor sub-agent for each sub-task in parallel.
func (o *Orchestrator) runExecutorsParallel(ctx context.Context, planOutput string, subTasks []subTask, maxParallel int) []agentResult {
	return runParallel(subTasks, maxParallel, func(st subTask) agentResult {
		out, err := o.runSingleExecutor(ctx, st.desc, st.module, planOutput)
		return agentResult{module: st.module, output: out, err: err}
	})
}

type subTask struct {
	module string
	desc   string
}

// decomposeTask splits a task into per-module sub-tasks.
func (o *Orchestrator) decomposeTask(task string, modules []string) []subTask {
	if len(modules) <= 1 {
		return []subTask{{module: modules[0], desc: task}}
	}
	var tasks []subTask
	for _, m := range modules {
		tasks = append(tasks, subTask{module: m, desc: fmt.Sprintf("%s (focus on module: %s)", task, m)})
	}
	return tasks
}

// runParallel is a generic parallel executor with bounded concurrency.
func runParallel[T any](items []T, maxParallel int, fn func(T) agentResult) []agentResult {
	if len(items) == 0 {
		return nil
	}
	if maxParallel > len(items) {
		maxParallel = len(items)
	}

	type work struct {
		idx  int
		item T
	}

	jobs := make(chan work, len(items))
	results := make([]agentResult, len(items))

	var wg sync.WaitGroup
	for w := 0; w < maxParallel; w++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			for job := range jobs {
				results[job.idx] = fn(job.item)
			}
		}(w)
	}

	for i, item := range items {
		jobs <- work{idx: i, item: item}
	}
	close(jobs)
	wg.Wait()

	return results
}

func (o *Orchestrator) runSingleExecutor(ctx context.Context, task, module, planOutput string) (string, error) {
	return o.runExecutor(ctx, task, module, planOutput)
}

// ---- Individual role sub-agent runners ----

func (o *Orchestrator) runPlanner(ctx context.Context, task, module string) (string, error) {
	sysPrompt := fmt.Sprintf(`You are the Planner agent in the Evergreen multi-agent federation.
Role: Task decomposition and interface contract design.
Model tier: Deep-thinking.

Your job: Given a task description and target module, produce a structured plan:
1. Break the task into sub-tasks (each < 100 lines of change)
2. Identify which modules are involved
3. Identify any interface contracts needed between modules
4. Assess risk level (low/medium/high)

Module context: %s
Relevant experience will be injected below.`, module)

	// Inject relevant experience
	patterns, antipatterns, constraints := o.store.InjectForTask(module, task)

	var sb strings.Builder
	sb.WriteString(sysPrompt)
	sb.WriteString("\n\n")

	if len(constraints) > 0 {
		sb.WriteString("## Hard Constraints\n")
		for _, c := range constraints {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", c.Title, c.Body))
		}
	}
	if len(antipatterns) > 0 {
		sb.WriteString("\n## Anti-patterns to Avoid\n")
		for _, a := range antipatterns {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", a.Title, a.Body))
		}
	}
	if len(patterns) > 0 {
		sb.WriteString("\n## Recommended Patterns\n")
		for _, p := range patterns {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", p.Title, p.Body))
		}
	}

	sb.WriteString(fmt.Sprintf("\n## Task\n%s\n\n", task))
	sb.WriteString("Produce a concise plan. Use tools (code_search, read_file) to understand the codebase before planning.")

	return o.runSubAgent(ctx, o.deepProv, "planner", sysPrompt,
		fmt.Sprintf("Plan this task for module '%s': %s", module, task),
		true) // read-only
}

func (o *Orchestrator) runKeeper(ctx context.Context, task, module, planOutput string) (string, error) {
	sysPrompt := fmt.Sprintf(`You are the Module Keeper for '%s' in the Evergreen federation.
Role: Code review authority with OWNERS responsibility.
Model tier: Quick-thinking.

Your job: Review the Planner's output and validate:
1. Are the sub-tasks appropriate for this module?
2. Are there any missing dependencies or contract needs?
3. Is the risk assessment accurate?
4. Are there experience cards that should be applied?

You have OWNERS authority for module '%s'.`, module, module)

	prompt := fmt.Sprintf("Planner output:\n%s\n\nTask: %s\nModule: %s\n\nReview this plan. Is it sound? What should be adjusted?",
		planOutput, task, module)

	return o.runSubAgent(ctx, o.prov, "keeper", sysPrompt, prompt, true)
}

func (o *Orchestrator) runExecutor(ctx context.Context, task, module, planOutput string) (string, error) {
	sysPrompt := `You are a Task Executor in the Evergreen federation.
Role: Implement code changes following the plan.
Model tier: Quick-thinking.

Your job: Execute the plan produced by the Planner. You have access to read/write tools.
Follow the 11-step workflow:
1. Read relevant experience cards
2. Read project rules (AGENT_CONTRIBUTING.md)
3. Analyze the architecture (read files, understand patterns)
4. Confirm the approach is sound
5. Write the code changes
6. Write tests
7. Run the new tests
8. Run all tests to check for regressions
9. Update documentation if needed
10. Write an experience card draft for what you learned
11. Record what you did for PR history

IMPORTANT: Always read before writing. Follow existing patterns in the codebase.`

	prompt := fmt.Sprintf("Plan:\n%s\n\nTask: %s\nModule: %s\n\nExecute this task. Use read_file to understand the existing code first, then make your changes.", planOutput, task, module)

	return o.runSubAgent(ctx, o.prov, "executor", sysPrompt, prompt, false) // write-capable
}

func (o *Orchestrator) runInspector(ctx context.Context, module string) (string, error) {
	sysPrompt := `You are the Inspector agent in the Evergreen federation.
Role: Read-only code health scanner.
Model tier: Quick-thinking.

Your job: Scan the codebase for:
1. Anti-patterns (print() statements, missing mounted checks, raw Dio() usage, hardcoded cookies)
2. Tech debt items
3. Contract violations
4. Overall code health assessment

You are READ-ONLY. You cannot modify code. Report what you find.`

	prompt := fmt.Sprintf("Scan module '%s' for code health issues. Look for anti-patterns, tech debt, and contract violations.", module)

	return o.runSubAgent(ctx, o.prov, "inspector", sysPrompt, prompt, true)
}

func (o *Orchestrator) runLibrarian(ctx context.Context, task, module, execOutput string) (string, error) {
	sysPrompt := `You are the Librarian agent in the Evergreen federation.
Role: Experience card curator.
Model tier: Deep-thinking.

Your job: After a task completes, determine if an experience card should be created:
1. Was something new learned? → Create a pattern card
2. Was a mistake made? → Create an anti-pattern card
3. Was a hard rule applied? → Create a constraint card
4. Was an approach impossible? → Create a dead_end card

Check for duplicates before creating. If the experience already exists, suggest updating it.`

	prompt := fmt.Sprintf("Task completed: %s (module: %s)\n\nExecutor output:\n%s\n\nShould any experience cards be created or updated?",
		task, module, truncateStr(execOutput, 2000))

	return o.runSubAgent(ctx, o.deepProv, "librarian", sysPrompt, prompt, true)
}

// ---- Core sub-agent runner ----

func (o *Orchestrator) runSubAgent(
	ctx context.Context,
	prov provider.Provider,
	role, sysPrompt, prompt string,
	readOnly bool,
) (string, error) {
	// Build scoped tool registry for this role
	roleToolNames := tool.RoleToolSets[role]
	if roleToolNames == nil {
		roleToolNames = tool.RoleToolSets["planner"] // fallback
	}

	var subReg *tool.Registry
	if readOnly {
		subReg = agent.ReadOnlySubagentToolRegistry(o.parentReg, roleToolNames)
	} else {
		subReg = agent.SubagentToolRegistry(o.parentReg, roleToolNames)
	}

	// Create fresh session with role-specific system prompt
	sess := agent.NewSession(sysPrompt)

	// Build options
	opts := agent.Options{
		MaxSteps:     o.maxSteps,
		Temperature:  o.temperature,
		UsageSource:  event.UsageSourceSubagent,
		Gate:         o.headlessGate,
		ContextWindow: o.ctxWindow,
		ArchiveDir:   o.archiveDir,
	}

	// Emit phase boundary
	o.sink.Emit(event.Event{
		Kind: event.Phase,
		Text: fmt.Sprintf("reasonix_gr · %s", role),
		Federation: &event.FederationPayload{
			System: &event.FederationSystem{AgentID: fmt.Sprintf("eva-%s", role)},
		},
	})

	// Run the sub-agent
	answer, err := agent.RunSubAgentWithSession(ctx, prov, subReg, sess, prompt, opts, o.sink)
	if err != nil {
		return "", fmt.Errorf("%s sub-agent: %w", role, err)
	}

	return answer, nil
}

func truncateStr(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
