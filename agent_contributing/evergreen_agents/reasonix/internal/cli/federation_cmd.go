package cli

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"

	"reasonix_gr/internal/config"
	"reasonix_gr/internal/evergreen/bootstrap"
	"reasonix_gr/internal/evergreen/contracts"
	"reasonix_gr/internal/evergreen/experience"
	"reasonix_gr/internal/evergreen/federation"
	"reasonix_gr/internal/evergreen/types"
	"reasonix_gr/internal/permission"
	"reasonix_gr/internal/provider"
	"reasonix_gr/internal/tool"
)

func bootstrapCommand(rest []string) int {
	fs := flag.NewFlagSet("bootstrap", flag.ContinueOnError)
	registryPath := fs.String("registry", "agent_contributing/evergreen_agents/config/module_registry.yaml", "")
	experiencesDir := fs.String("experiences", "agent_contributing/experiences", "")
	workspaceRoot := fs.String("root", ".", "")
	dryRun := fs.Bool("dry-run", false, "")
	fs.Parse(rest)

	if *dryRun {
		fmt.Println("[dry-run] Would bootstrap with:")
		fmt.Printf("  registry: %s\n  experiences: %s\n  root: %s\n", *registryPath, *experiencesDir, *workspaceRoot)
		return 0
	}
	result, err := bootstrap.Bootstrap(*registryPath, *experiencesDir, *workspaceRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bootstrap failed: %v\n", err)
		return 1
	}
	fmt.Printf("=== Bootstrap ===\nKeepers: %d | OWNERS: %d | Cards: %d loaded, %d approved\n",
		result.ModuleKeepers, result.OwnersFilesWritten, result.CardsLoaded, result.CardsApproved)
	return 0
}

func experienceCommand(rest []string) int {
	if len(rest) == 0 {
		fmt.Println("Usage: reasonix_gr experience <search|stats|index>")
		return 1
	}
	switch rest[0] {
	case "search":
		return experienceSearch(rest[1:])
	case "stats":
		return experienceStats(rest[1:])
	case "index":
		return experienceIndex(rest[1:])
	default:
		fmt.Fprintf(os.Stderr, "unknown: %s\n", rest[0])
		return 1
	}
}

func experienceSearch(rest []string) int {
	fs := flag.NewFlagSet("search", flag.ContinueOnError)
	cardType := fs.String("type", "", "")
	module := fs.String("module", "", "")
	limit := fs.Int("limit", 10, "")
	fs.Parse(rest)
	query := strings.Join(fs.Args(), " ")

	store := experience.NewStore("agent_contributing/experiences")
	store.LoadFromDisk()
	var tf *types.ExperienceType
	if *cardType != "" {
		t := types.ExperienceType(*cardType)
		tf = &t
	}
	results := store.Search(query, tf, *module, nil, *limit)
	if len(results) == 0 {
		fmt.Println("No matching cards.")
		return 0
	}
	for _, r := range results {
		fmt.Printf("### %s (%s) score:%.0f\n  %s\n\n", r.Card.Title, r.Card.Type, r.Score, r.Card.Body)
	}
	return 0
}

func experienceStats(rest []string) int {
	store := experience.NewStore("agent_contributing/experiences")
	store.LoadFromDisk()
	b, _ := json.MarshalIndent(store.Stats(), "", "  ")
	fmt.Println(string(b))
	return 0
}

func experienceIndex(rest []string) int {
	path := "EXPERIENCE.md"
	if len(rest) > 0 {
		path = rest[0]
	}
	idx, err := bootstrap.RebuildIndex("agent_contributing/experiences", path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	fmt.Println(idx)
	return 0
}

func moduleCommand(rest []string) int {
	if len(rest) == 0 {
		fmt.Println("Usage: reasonix_gr module <list|deps|contracts|owner>")
		return 1
	}
	switch rest[0] {
	case "list":
		return moduleList(rest[1:])
	case "deps":
		return moduleDeps(rest[1:])
	case "contracts":
		return moduleContracts(rest[1:])
	case "owner":
		return moduleOwner(rest[1:])
	default:
		fmt.Fprintf(os.Stderr, "unknown: %s\n", rest[0])
		return 1
	}
}

func moduleList(rest []string) int {
	reg, err := loadRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	fmt.Printf("%-20s %-15s %-10s %s\n", "MODULE", "SECTION", "STATUS", "PATH")
	for _, m := range reg.ModulesAsList() {
		fmt.Printf("%-20s %-15s %-10s %s\n", m.Slug, m.Section, m.Status, m.Path)
	}
	return 0
}

func moduleDeps(rest []string) int {
	fs := flag.NewFlagSet("deps", flag.ContinueOnError)
	module := fs.String("module", "", "")
	fs.Parse(rest)
	if *module == "" {
		fmt.Println("Usage: reasonix_gr module deps --module <name>")
		return 1
	}
	reg, err := loadRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	for _, m := range reg.ModulesAsList() {
		if m.Slug == *module {
			fmt.Printf("%s (%s): depends_on=%s depended_by=%s\n", m.Slug, m.Section, m.DependsOn, m.DependedBy)
			return 0
		}
	}
	fmt.Fprintf(os.Stderr, "not found: %s\n", *module)
	return 1
}

func moduleContracts(rest []string) int {
	fs := flag.NewFlagSet("contracts", flag.ContinueOnError)
	module := fs.String("module", "", "")
	fs.Parse(rest)
	if *module == "" {
		fmt.Println("Usage: reasonix_gr module contracts --module <name>")
		return 1
	}
	cm := contracts.NewModel()
	for _, c := range cm.ActiveForModule(*module) {
		fmt.Printf("[%s] %s ↔ %s\n", c.ContractID, c.FromModule, c.ToModule)
	}
	return 0
}

func moduleOwner(rest []string) int {
	fs := flag.NewFlagSet("owner", flag.ContinueOnError)
	module := fs.String("module", "", "")
	fs.Parse(rest)
	or, err := bootstrap.CreateOwnersRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		return 1
	}
	if *module != "" {
		fmt.Printf("OWNERS(%s): %s\n", *module, strings.Join(or.OwnersOf(*module), ", "))
	} else {
		reg, _ := loadRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
		if reg != nil {
			for _, m := range reg.ModulesAsList() {
				fmt.Printf("%-20s → %s\n", m.Slug, strings.Join(or.OwnersOf(m.Slug), ", "))
			}
		}
	}
	return 0
}

func inspectCommand(rest []string) int {
	fs := flag.NewFlagSet("inspect", flag.ContinueOnError)
	module := fs.String("module", "", "")
	fs.Parse(rest)
	fmt.Printf("=== Inspector: %s ===\n", orEmpty(*module, "all"))
	reg, _ := loadRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
	if reg != nil {
		for _, m := range reg.ModulesAsList() {
			fmt.Printf("  %s (%s)\n", m.Slug, m.Status)
		}
	}
	return 0
}

func federationCommand(rest []string) int {
	if len(rest) > 0 && rest[0] == "run" {
		rest = rest[1:]
	}
	fs := flag.NewFlagSet("federation", flag.ContinueOnError)
	task := fs.String("task", "", "")
	module := fs.String("module", "", "")
	fs.Parse(rest)
	if *task == "" {
		fmt.Println("Usage: reasonix_gr federation run --task \"...\" [--module <name>]")
		return 1
	}
	fleet := setupFleet()
	if fleet == nil {
		return 1
	}
	defer fleet.Save()

	status := fleet.Status()
	fmt.Printf("=== Fleet: %d agents | %d idle ===\n\n", status.TotalAgents, status.IdleAgents)

	ctx := context.Background()
	result, err := fleet.RunTask(ctx, *task, *module)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed: %v\n", err)
		return 1
	}
	fmt.Printf("Task: %s | Module: %s | Status: %s\n", *task, *module, result.Status)
	fmt.Printf("Involved: %d | Idle: %d\n", result.AgentsInvolved, result.AgentsIdle)
	if result.KeeperReview != "" {
		fmt.Printf("\n--- Keeper ---\n%s\n", truncate(result.KeeperReview, 500))
	}
	if result.ExecutorOutput != "" {
		fmt.Printf("\n--- Executor ---\n%s\n", truncate(result.ExecutorOutput, 800))
	}
	return 0
}

func agentCommand(rest []string) int {
	if len(rest) == 0 {
		fmt.Println("Usage: reasonix_gr agent <list|credit>")
		return 1
	}
	switch rest[0] {
	case "list":
		return agentList(rest[1:])
	case "credit":
		return agentCredit(rest[1:])
	default:
		return 1
	}
}

func agentList(rest []string) int {
	reg, err := loadRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
	if err != nil {
		return 1
	}
	fmt.Printf("%-25s %-15s %s\n", "AGENT", "ROLE", "MODULE")
	fmt.Printf("%-25s %-15s %s\n", "eva-planner", "planner", "(global)")
	for _, m := range reg.ModulesAsList() {
		fmt.Printf("%-25s %-15s %s\n", "eva-keeper-"+m.Slug, "module_keeper", m.Slug)
	}
	fmt.Printf("%-25s %-15s %s\n", "eva-inspector", "inspector", "(global)")
	fmt.Printf("%-25s %-15s %s\n", "eva-librarian", "librarian", "(global)")
	return 0
}

func agentCredit(rest []string) int {
	fs := flag.NewFlagSet("credit", flag.ContinueOnError)
	agent := fs.String("agent", "", "")
	fs.Parse(rest)
	if *agent == "" && len(fs.Args()) > 0 {
		*agent = fs.Args()[0]
	}
	cs := types.NewCreditScore(*agent, types.RoleTaskExecutor)
	fmt.Printf("Agent: %s | Role: %s | Tier: %s | Composite: %.1f\n", cs.AgentID, cs.Role, cs.Tier(), cs.Composite)
	return 0
}

func auditCommand(rest []string) int {
	fs := flag.NewFlagSet("audit", flag.ContinueOnError)
	limit := fs.Int("limit", 20, "")
	fs.Parse(rest)
	fmt.Printf("=== Audit (limit=%d) ===\n(no records yet)\n", *limit)
	return 0
}

// ---- Helpers ----

func orEmpty(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

func loadRegistry(path string) (*bootstrap.ModuleRegistry, error) {
	return bootstrap.LoadModuleRegistry(path)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "\n..."
}

// setupFleet builds a Fleet from config.
func setupFleet() *federation.Fleet {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "load config: %v\n", err)
		return nil
	}
	modelName := cfg.DefaultModel
	if modelName == "" {
		modelName = "deepseek-flash"
	}
	entry, ok := cfg.Provider(modelName)
	if !ok {
		fmt.Fprintf(os.Stderr, "model not found: %s\n", modelName)
		return nil
	}
	prov, err := provider.New(entry.Kind, provider.Config{
		Name: entry.Name, BaseURL: entry.BaseURL, Model: entry.DefaultModel(), APIKey: entry.APIKey(),
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "provider: %v\n", err)
		return nil
	}
	var deepProv provider.Provider = prov
	if pe, ok := cfg.Provider("deepseek-pro"); ok {
		if dp, err := provider.New(pe.Kind, provider.Config{
			Name: pe.Name, BaseURL: pe.BaseURL, Model: pe.DefaultModel(), APIKey: pe.APIKey(),
		}); err == nil {
			deepProv = dp
		}
	}
	reg := tool.NewRegistry()
	if len(cfg.Tools.Enabled) == 0 {
		for _, t := range tool.Builtins() {
			reg.Add(t)
		}
	} else {
		for _, name := range cfg.Tools.Enabled {
			if t, ok := tool.LookupBuiltin(name); ok {
				reg.Add(t)
			}
		}
	}
	store := experience.NewStore("agent_contributing/experiences")
	store.LoadFromDisk()

	fleet := federation.NewFleet(federation.FleetOpts{
		QuickProvider: prov, DeepProvider: deepProv, Registry: reg, Store: store,
		Policy: permission.Policy{Mode: permission.Allow},
		MaxSteps: cfg.Agent.MaxSteps, Temperature: cfg.Agent.Temperature,
		ContextWindow: 131072, ArchiveDir: config.ArchiveDir(),
	})
	modReg, err := bootstrap.LoadModuleRegistry("agent_contributing/evergreen_agents/config/module_registry.yaml")
	if err == nil {
		var modules []string
		for _, m := range modReg.ModulesAsList() {
			modules = append(modules, m.Slug)
		}
		fleet.CommissionModules(modules)
	}
	return fleet
}
