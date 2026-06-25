// Package types defines all domain types for the Evergreen multi-agent federation
// system. It mirrors the Python src/core/types.py + src/agents/schemas.py.
//
// All framework components import from here. Zero internal dependencies beyond the
// Go standard library.
package types

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func newID(prefix string) string {
	b := make([]byte, 4)
	rand.Read(b)
	return prefix + "-" + hex.EncodeToString(b)
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

// AgentRole mirrors Python AgentRole enum (§2.1 蓝图).
type AgentRole string

const (
	RolePlanner      AgentRole = "planner"
	RoleModuleKeeper AgentRole = "module_keeper"
	RoleTaskExecutor AgentRole = "task_executor"
	RoleInspector    AgentRole = "inspector"
	RoleLibrarian    AgentRole = "librarian"
)

// ValidAgentRole checks whether s is a known agent role.
func ValidAgentRole(s string) (AgentRole, bool) {
	r := AgentRole(s)
	switch r {
	case RolePlanner, RoleModuleKeeper, RoleTaskExecutor, RoleInspector, RoleLibrarian:
		return r, true
	}
	return "", false
}

// AgentStatus mirrors Python AgentStatus enum.
type AgentStatus string

const (
	AgentIdle          AgentStatus = "idle"
	AgentBusy          AgentStatus = "busy"
	AgentWaitingReview AgentStatus = "waiting_review"
	AgentWaitingHuman  AgentStatus = "waiting_human"
	AgentError         AgentStatus = "error"
	AgentOffline       AgentStatus = "offline"
)

// TaskStatus mirrors Python TaskStatus enum (11 states).
type TaskStatus string

const (
	TaskPending     TaskStatus = "pending"
	TaskPlanning    TaskStatus = "planning"
	TaskContracting TaskStatus = "contracting"
	TaskAssigned    TaskStatus = "assigned"
	TaskInProgress  TaskStatus = "in_progress"
	TaskInReview    TaskStatus = "in_review"
	TaskInMergeQ    TaskStatus = "in_merge_queue"
	TaskCompleted   TaskStatus = "completed"
	TaskFailed      TaskStatus = "failed"
	TaskRejected    TaskStatus = "rejected"
	TaskBlocked     TaskStatus = "blocked"
)

// IsTerminal returns true for task states that will not change further.
func (s TaskStatus) IsTerminal() bool {
	return s == TaskCompleted || s == TaskFailed || s == TaskRejected
}

// ExperienceType mirrors Python ExperienceType enum.
type ExperienceType string

const (
	ExpPattern    ExperienceType = "pattern"
	ExpAntipattern ExperienceType = "antipattern"
	ExpConstraint ExperienceType = "constraint"
	ExpDeadEnd    ExperienceType = "dead_end"
	ExpLesson     ExperienceType = "lesson"
)

// CardStatus mirrors Python CardStatus enum.
type CardStatus string

const (
	CardProposed   CardStatus = "proposed"
	CardApproved   CardStatus = "approved"
	CardSuperseded CardStatus = "superseded"
	CardRejected    CardStatus = "rejected"
)

// Severity mirrors Python Severity enum.
type Severity string

const (
	SevInfo    Severity = "info"
	SevWarning Severity = "warning"
	SevBlocking Severity = "blocking"
)

// ContractStatus mirrors Python ContractStatus enum.
type ContractStatus string

const (
	ContractProposed   ContractStatus = "proposed"
	ContractAccepted   ContractStatus = "accepted"
	ContractRejected    ContractStatus = "rejected"
	ContractSuperseded ContractStatus = "superseded"
	ContractViolated   ContractStatus = "violated"
)

// ChangeRisk mirrors Python ChangeRisk enum.
type ChangeRisk string

const (
	RiskLow    ChangeRisk = "low"
	RiskMedium ChangeRisk = "medium"
	RiskHigh   ChangeRisk = "high"
)

// ChangeType is a literal for task change classification.
type ChangeType string

const (
	ChangeFeat    ChangeType = "feat"
	ChangeFix     ChangeType = "fix"
	ChangeRefactor ChangeType = "refactor"
	ChangeTest    ChangeType = "test"
	ChangeDocs    ChangeType = "docs"
	ChangeChore   ChangeType = "chore"
	ChangePerf    ChangeType = "perf"
)

// ReviewStatus mirrors the Python review gate states.
type ReviewStatus string

const (
	ReviewPending          ReviewStatus = "pending"
	ReviewApproved         ReviewStatus = "approved"
	ReviewRejected          ReviewStatus = "rejected"
	ReviewChangesRequested ReviewStatus = "changes_requested"
)

// CreditTier classifies agent credit standing.
type CreditTier string

const (
	TierExcellent CreditTier = "excellent"
	TierGood      CreditTier = "good"
	TierWarning   CreditTier = "warning"
	TierProbation CreditTier = "probation"
	TierSuspended CreditTier = "suspended"
)

// FederationStatus is the top-level outcome of a federation run.
type FederationStatus string

const (
	FedPending   FederationStatus = "pending"
	FedSuccess   FederationStatus = "success"
	FedFailed    FederationStatus = "failed"
	FedContested FederationStatus = "contested"
)

// ---------------------------------------------------------------------------
// Agent Identity
// ---------------------------------------------------------------------------

// AgentIdentity is the unique identity for each agent in the federation.
type AgentIdentity struct {
	AgentID     string      `json:"agent_id" yaml:"agent_id"`
	Role        AgentRole   `json:"role" yaml:"role"`
	DisplayName string      `json:"display_name" yaml:"display_name"`
	Module      string      `json:"module,omitempty" yaml:"module,omitempty"`
	Skills      []string    `json:"skills" yaml:"skills"`
	CreatedAt   time.Time   `json:"created_at" yaml:"created_at"`
	Status      AgentStatus `json:"status" yaml:"status"`
}

// NewAgentIdentity creates an identity with defaults.
func NewAgentIdentity(role AgentRole, displayName string) AgentIdentity {
	return AgentIdentity{
		AgentID:     newID("eva"),
		Role:        role,
		DisplayName: displayName,
		Skills:      []string{},
		CreatedAt:   time.Now(),
		Status:      AgentIdle,
	}
}

// Validate checks required fields.
func (a AgentIdentity) Validate() error {
	if a.AgentID == "" {
		return fmt.Errorf("agent_id is required")
	}
	if _, ok := ValidAgentRole(string(a.Role)); !ok {
		return fmt.Errorf("invalid agent role: %s", a.Role)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Task Spec & Task Tree (from 蓝图 §2.2)
// ---------------------------------------------------------------------------

// TaskSpec is a single leaf task in the task tree.
type TaskSpec struct {
	TaskID          string     `json:"task_id" yaml:"task_id"`
	Title           string     `json:"title" yaml:"title"`
	Description     string     `json:"description" yaml:"description"`
	Module          string     `json:"module" yaml:"module"`
	ChangeType      ChangeType `json:"change_type" yaml:"change_type"`
	EstimatedLines  int        `json:"estimated_lines" yaml:"estimated_lines"`
	Dependencies    []string   `json:"dependencies" yaml:"dependencies"`
	ContractsNeeded []string   `json:"contracts_needed" yaml:"contracts_needed"`
	Status          TaskStatus `json:"status" yaml:"status"`
	AssignedAgent   string     `json:"assigned_agent,omitempty" yaml:"assigned_agent,omitempty"`
	FeatureFlag     string     `json:"feature_flag,omitempty" yaml:"feature_flag,omitempty"`
	CreatedAt       time.Time  `json:"created_at" yaml:"created_at"`
	CompletedAt     *time.Time `json:"completed_at,omitempty" yaml:"completed_at,omitempty"`
}

// NewTaskSpec creates a TaskSpec with defaults. Target < 100 lines (蓝图 A.2).
func NewTaskSpec(title, description, module string, changeType ChangeType) TaskSpec {
	return TaskSpec{
		TaskID:         newID("task"),
		Title:          title,
		Description:    description,
		Module:         module,
		ChangeType:     changeType,
		EstimatedLines: 50,
		Dependencies:   []string{},
		ContractsNeeded: []string{},
		Status:         TaskPending,
		CreatedAt:      time.Now(),
	}
}

// Validate checks required fields.
func (t TaskSpec) Validate() error {
	if t.TaskID == "" {
		return fmt.Errorf("task_id is required")
	}
	if t.Title == "" {
		return fmt.Errorf("title is required")
	}
	if t.Module == "" {
		return fmt.Errorf("module is required")
	}
	return nil
}

// TaskTree is a tree of tasks produced by the Planner.
type TaskTree struct {
	TreeID          string              `json:"tree_id" yaml:"tree_id"`
	RootTask        string              `json:"root_task" yaml:"root_task"`
	RootID          string              `json:"root_id" yaml:"root_id"`
	Nodes           map[string]TaskSpec `json:"nodes" yaml:"nodes"`
	Edges           map[string][]string `json:"edges" yaml:"edges"`
	Contracts       map[string]Contract `json:"contracts" yaml:"contracts"`
	ModulesInvolved []string            `json:"modules_involved" yaml:"modules_involved"`
	CreatedAt       time.Time           `json:"created_at" yaml:"created_at"`
	Status          string              `json:"status" yaml:"status"` // active | completed | failed
}

// NewTaskTree creates an empty task tree.
func NewTaskTree(rootTask, rootID string) TaskTree {
	return TaskTree{
		TreeID:    newID("tree"),
		RootTask:  rootTask,
		RootID:    rootID,
		Nodes:     map[string]TaskSpec{},
		Edges:     map[string][]string{},
		Contracts: map[string]Contract{},
		CreatedAt: time.Now(),
		Status:    "active",
	}
}

// ---------------------------------------------------------------------------
// Interface Contracts (from 蓝图 §2.2 契约先行)
// ---------------------------------------------------------------------------

// Contract is an interface contract between two modules.
type Contract struct {
	ContractID    string                 `json:"contract_id" yaml:"contract_id"`
	FromModule    string                 `json:"from_module" yaml:"from_module"`
	ToModule      string                 `json:"to_module" yaml:"to_module"`
	Title         string                 `json:"title" yaml:"title"`
	Description   string                 `json:"description" yaml:"description"`
	InterfaceSpec map[string]interface{} `json:"interface_spec" yaml:"interface_spec"`
	Status        ContractStatus         `json:"status" yaml:"status"`
	ProposedBy    string                 `json:"proposed_by" yaml:"proposed_by"`
	ApprovedBy    map[string]string      `json:"approved_by" yaml:"approved_by"` // module -> agent_id
	SupersededBy  string                 `json:"superseded_by,omitempty" yaml:"superseded_by,omitempty"`
	CreatedAt     time.Time              `json:"created_at" yaml:"created_at"`
}

// NewContract creates a proposed contract.
func NewContract(fromModule, toModule, title, description string, spec map[string]interface{}) Contract {
	return Contract{
		ContractID:    newID("ctr"),
		FromModule:    fromModule,
		ToModule:      toModule,
		Title:         title,
		Description:   description,
		InterfaceSpec: spec,
		Status:        ContractProposed,
		ApprovedBy:    map[string]string{},
		CreatedAt:     time.Now(),
	}
}

// ---------------------------------------------------------------------------
// Experience Cards
// ---------------------------------------------------------------------------

// ExperienceCard is an experience card — markdown frontmatter + body.
type ExperienceCard struct {
	ID           string          `json:"id" yaml:"id"`
	Type         ExperienceType  `json:"type" yaml:"type"`
	Title        string          `json:"title" yaml:"title"`
	Tags         []string        `json:"tags" yaml:"tags"`
	CreatedDate  string          `json:"created_date" yaml:"created_date"` // ISO date
	Module       string          `json:"module,omitempty" yaml:"module,omitempty"`
	SourceAgent  string          `json:"source_agent" yaml:"source_agent"`
	SourceTask   string          `json:"source_task" yaml:"source_task"`
	Signature    string          `json:"signature" yaml:"signature"` // AST-based fingerprint
	Severity     Severity        `json:"severity" yaml:"severity"`
	Status       CardStatus      `json:"status" yaml:"status"`
	Body         string          `json:"body" yaml:"body"`
	Embedding    []float64       `json:"embedding,omitempty" yaml:"-"`
	Version      int             `json:"version" yaml:"version"`
	SupersededBy string          `json:"superseded_by,omitempty" yaml:"superseded_by,omitempty"`
	Supersedes   string          `json:"supersedes,omitempty" yaml:"supersedes,omitempty"`
	FilePath     string          `json:"file_path" yaml:"file_path"`
}

// NewExperienceCard creates a card with defaults.
func NewExperienceCard(t ExperienceType, title string) ExperienceCard {
	return ExperienceCard{
		ID:          newID("exp"),
		Type:        t,
		Title:       title,
		Tags:        []string{},
		CreatedDate: time.Now().Format("2006-01-02"),
		Severity:    SevInfo,
		Status:      CardProposed,
		Version:     1,
	}
}

// Date returns the CreatedDate for backward-compatible access.
func (c ExperienceCard) Date() string { return c.CreatedDate }

// ToMarkdown serializes the card to markdown with YAML frontmatter.
func (c ExperienceCard) ToMarkdown() string {
	tagStr := strings.Join(c.Tags, ", ")
	outcome := string(c.Status)
	if c.Status == CardApproved {
		outcome = "success"
	}

	var b strings.Builder
	b.WriteString("---\n")
	fmt.Fprintf(&b, "id: %s\n", c.ID)
	fmt.Fprintf(&b, "type: %s\n", c.Type)
	fmt.Fprintf(&b, "title: %s\n", c.Title)
	fmt.Fprintf(&b, "tags: [%s]\n", tagStr)
	fmt.Fprintf(&b, "date: %s\n", c.CreatedDate)
	if c.Module != "" {
		fmt.Fprintf(&b, "module: %s\n", c.Module)
	}
	fmt.Fprintf(&b, "severity: %s\n", c.Severity)
	fmt.Fprintf(&b, "status: %s\n", c.Status)
	fmt.Fprintf(&b, "outcome: %s\n", outcome)
	fmt.Fprintf(&b, "version: %d\n", c.Version)
	if c.SupersededBy != "" {
		fmt.Fprintf(&b, "superseded_by: %s\n", c.SupersededBy)
	}
	if c.Supersedes != "" {
		fmt.Fprintf(&b, "supersedes: %s\n", c.Supersedes)
	}
	b.WriteString("---\n\n")
	b.WriteString(c.Body)
	b.WriteString("\n")
	return b.String()
}

// FromMarkdown parses a markdown experience card. Handles both the new format
// (id/type/title/status/version in frontmatter) and the legacy format
// (task_type/tags/outcome/date without id/title).
func FromMarkdown(md, filePath string) ExperienceCard {
	c := ExperienceCard{FilePath: filePath, Status: CardProposed, Version: 1}
	lines := strings.Split(strings.TrimSpace(md), "\n")
	if len(lines) == 0 || strings.TrimSpace(lines[0]) != "---" {
		c.Body = md
		return c
	}

	// Find closing ---
	endIdx := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			endIdx = i
			break
		}
	}
	if endIdx < 0 {
		c.Body = md
		return c
	}

	fmLines := lines[1:endIdx]
	if endIdx+1 < len(lines) {
		c.Body = strings.TrimSpace(strings.Join(lines[endIdx+1:], "\n"))
	}

	// Parse frontmatter key: value pairs
	fm := map[string]string{}
	tagsList := []string{}
	inTags := false

	for _, line := range fmLines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if strings.HasPrefix(trimmed, "tags:") {
			inTags = true
			rest := strings.TrimPrefix(trimmed, "tags:")
			rest = strings.TrimSpace(rest)
			if strings.HasPrefix(rest, "[") && strings.HasSuffix(rest, "]") {
				inner := rest[1 : len(rest)-1]
				for _, t := range strings.Split(inner, ",") {
					t = strings.TrimSpace(t)
					t = strings.Trim(t, `"'`)
					if t != "" {
						tagsList = append(tagsList, t)
					}
				}
				inTags = false
			}
			continue
		}
		if inTags && strings.HasPrefix(trimmed, "- ") {
			t := strings.TrimPrefix(trimmed, "- ")
			t = strings.Trim(t, `"'`)
			if t != "" {
				tagsList = append(tagsList, t)
			}
			continue
		}
		inTags = false
		if idx := strings.Index(trimmed, ":"); idx >= 0 {
			key := strings.TrimSpace(trimmed[:idx])
			val := strings.TrimSpace(trimmed[idx+1:])
			fm[key] = val
		}
	}

	// --- Map fields ---

	// Type: from 'type' (new) or 'task_type' (legacy)
	typeStr := fm["type"]
	if typeStr == "" {
		typeStr = fm["task_type"]
	}
	typeMap := map[string]ExperienceType{
		"refactor":    ExpPattern,
		"feature":     ExpPattern,
		"bug-fix":     ExpAntipattern,
		"experiment":  ExpDeadEnd,
		"pattern":     ExpPattern,
		"antipattern": ExpAntipattern,
		"constraint":  ExpConstraint,
		"dead_end":    ExpDeadEnd,
		"lesson":      ExpLesson,
	}
	c.Type = ExpLesson
	if t, ok := typeMap[typeStr]; ok {
		c.Type = t
	}

	// ID
	c.ID = fm["id"]
	if c.ID == "" {
		c.ID = newID("exp")
	}

	// Title: from 'title' or derive from filename
	c.Title = fm["title"]
	if c.Title == "" && filePath != "" {
		stem := filepath.Base(filePath)
		stem = strings.TrimSuffix(stem, filepath.Ext(stem))
		stem = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}-`).ReplaceAllString(stem, "")
		c.Title = strings.ReplaceAll(strings.ReplaceAll(stem, "-", " "), "_", " ")
	}

	// Status: from 'status' (new) or 'outcome' (legacy)
	statusStr := fm["status"]
	if statusStr == "" {
		statusStr = fm["outcome"]
	}
	statusMap := map[string]CardStatus{
		"success":    CardApproved,
		"abandoned":  CardSuperseded,
		"failed":     CardRejected,
		"approved":   CardApproved,
		"proposed":   CardProposed,
		"superseded": CardSuperseded,
		"rejected":   CardRejected,
	}
	if s, ok := statusMap[statusStr]; ok {
		c.Status = s
	}

	// Tags
	c.Tags = tagsList
	if len(c.Tags) == 0 {
		tagsRaw := fm["tags"]
		tagsRaw = strings.Trim(tagsRaw, "[]")
		for _, t := range strings.Split(tagsRaw, ",") {
			t = strings.TrimSpace(t)
			t = strings.Trim(t, `"'`)
			if t != "" {
				c.Tags = append(c.Tags, t)
			}
		}
	}

	// Date
	c.CreatedDate = fm["date"]
	if c.CreatedDate == "" {
		c.CreatedDate = time.Now().Format("2006-01-02")
	}

	// Module: from 'module' or infer from tags
	c.Module = fm["module"]
	if c.Module == "" {
		moduleTags := map[string]string{
			"zdbk": "zdbk", "courses": "courses", "palace": "palace",
			"translate": "translate", "classroom": "classroom", "tutor": "tutor",
			"agent": "agent", "cache": "core_storage",
		}
		for _, tag := range c.Tags {
			if m, ok := moduleTags[tag]; ok {
				c.Module = m
				break
			}
		}
	}

	// Severity
	sevStr := fm["severity"]
	if sevStr == "" {
		sevStr = fm["difficulty"]
	}
	sevMap := map[string]string{"hard": "warning", "medium": "info", "easy": "info", "blocking": "blocking"}
	if mapped, ok := sevMap[sevStr]; ok {
		sevStr = mapped
	}
	switch sevStr {
	case "warning":
		c.Severity = SevWarning
	case "blocking":
		c.Severity = SevBlocking
	default:
		c.Severity = SevInfo
	}

	// Version
	if v := fm["version"]; v != "" {
		fmt.Sscanf(v, "%d", &c.Version)
	}

	// Supersedes / superseded_by
	c.SupersededBy = fm["superseded_by"]
	c.Supersedes = fm["supersedes"]

	// Source
	c.SourceAgent = fm["source_agent"]
	c.SourceTask = fm["source_task"]

	return c
}

// ---------------------------------------------------------------------------
// Credit Scoring (from 蓝图.md §4 Owner终极责任)
// ---------------------------------------------------------------------------

// CreditScore is the multi-dimensional credit score for each agent.
type CreditScore struct {
	AgentID string    `json:"agent_id" yaml:"agent_id"`
	Role    AgentRole `json:"role" yaml:"role"`

	CodeQuality        float64 `json:"code_quality" yaml:"code_quality"`
	TestQuality        float64 `json:"test_quality" yaml:"test_quality"`
	ReviewAccuracy     float64 `json:"review_accuracy" yaml:"review_accuracy"`
	ExperienceQuality  float64 `json:"experience_quality" yaml:"experience_quality"`
	ErrorBudgetRespect float64 `json:"error_budget_respect" yaml:"error_budget_respect"`
	Collaboration      float64 `json:"collaboration" yaml:"collaboration"`

	Composite float64 `json:"composite" yaml:"composite"`

	TotalTasks      int        `json:"total_tasks" yaml:"total_tasks"`
	TotalApprovals  int        `json:"total_approvals" yaml:"total_approvals"`
	TotalRejections int        `json:"total_rejections" yaml:"total_rejections"`
	LastEvaluated   *time.Time `json:"last_evaluated,omitempty" yaml:"last_evaluated,omitempty"`
}

// NewCreditScore creates a default score for an agent.
func NewCreditScore(agentID string, role AgentRole) CreditScore {
	return CreditScore{
		AgentID:            agentID,
		Role:               role,
		CodeQuality:        100.0,
		TestQuality:        100.0,
		ReviewAccuracy:     100.0,
		ExperienceQuality:  100.0,
		ErrorBudgetRespect: 100.0,
		Collaboration:      100.0,
		Composite:          100.0,
	}
}

// Tier returns the credit tier classification.
func (cs CreditScore) Tier() CreditTier {
	switch {
	case cs.Composite >= 90:
		return TierExcellent
	case cs.Composite >= 75:
		return TierGood
	case cs.Composite >= 60:
		return TierWarning
	case cs.Composite >= 40:
		return TierProbation
	default:
		return TierSuspended
	}
}

// ---------------------------------------------------------------------------
// Decision Audit
// ---------------------------------------------------------------------------

// AuditContext captures the context of an agent decision.
type AuditContext struct {
	TaskID                  string   `json:"task_id" yaml:"task_id"`
	Module                  string   `json:"module" yaml:"module"`
	FilesTouched            []string `json:"files_touched" yaml:"files_touched"`
	ContractsReferenced     []string `json:"contracts_referenced" yaml:"contracts_referenced"`
	ExperienceCardsConsulted []string `json:"experience_cards_consulted" yaml:"experience_cards_consulted"`
	ModelUsed               string   `json:"model_used" yaml:"model_used"`
	TurnNumber              int      `json:"turn_number" yaml:"turn_number"`
}

// AuditRecord is an immutable record of a single agent decision.
type AuditRecord struct {
	ID           string       `json:"id" yaml:"id"`
	Timestamp    time.Time    `json:"timestamp" yaml:"timestamp"`
	AgentID      string       `json:"agent_id" yaml:"agent_id"`
	AgentRole    AgentRole    `json:"agent_role" yaml:"agent_role"`
	DecisionType string       `json:"decision_type" yaml:"decision_type"`
	Context      AuditContext `json:"context" yaml:"context"`
	Decision     string       `json:"decision" yaml:"decision"`
	Rationale    string       `json:"rationale" yaml:"rationale"`
	Evidence     []string     `json:"evidence" yaml:"evidence"`
	Alternatives []string     `json:"alternatives" yaml:"alternatives"`
	Outcome      string       `json:"outcome,omitempty" yaml:"outcome,omitempty"`
}

// NewAuditRecord creates an audit record with defaults.
func NewAuditRecord(agentID string, role AgentRole, decisionType string) AuditRecord {
	return AuditRecord{
		ID:           newID("audit"),
		Timestamp:    time.Now(),
		AgentID:      agentID,
		AgentRole:    role,
		DecisionType: decisionType,
		Context:      AuditContext{},
		Evidence:     []string{},
		Alternatives: []string{},
	}
}

// ToJSONL serializes the record as a single JSON line.
func (r AuditRecord) ToJSONL() string {
	b, _ := json.Marshal(r)
	return string(b)
}

// ---------------------------------------------------------------------------
// Module Definition
// ---------------------------------------------------------------------------

// ModuleSpec defines a code module in the federation.
type ModuleSpec struct {
	Name                 string   `json:"name" yaml:"name"`
	Path                 string   `json:"path" yaml:"path"`
	Description          string   `json:"description" yaml:"description"`
	Owners               []string `json:"owners" yaml:"owners"`         // agent_ids of keepers
	Contracts            []string `json:"contracts" yaml:"contracts"`   // contract_ids
	OnboardingDoc        string   `json:"onboarding_doc" yaml:"onboarding_doc"`
	ADRs                 []string `json:"adrs" yaml:"adrs"`
	TechDebtItems        int      `json:"tech_debt_items" yaml:"tech_debt_items"`
	ErrorBudgetRemaining float64  `json:"error_budget_remaining" yaml:"error_budget_remaining"`
}

// ---------------------------------------------------------------------------
// Agent Federation State (from TradingAgents StateGraph pattern)
// ---------------------------------------------------------------------------

// DebaterPosition records one debater's stance.
type DebaterPosition struct {
	AgentID  string   `json:"agent_id"`
	Stance   string   `json:"stance"` // for | against | neutral
	Argument string   `json:"argument"`
	Evidence []string `json:"evidence"`
}

// DebateState tracks the state of a debate round.
type DebateState struct {
	Round     int              `json:"round"`
	MaxRounds int              `json:"max_rounds"`
	Positions []DebaterPosition `json:"positions"`
	Resolved  bool             `json:"resolved"`
}

// ModuleContext is per-module runtime state during a federation run.
type ModuleContext struct {
	ModuleName     string   `json:"module_name"`
	KeeperAgentID  string   `json:"keeper_agent_id"`
	QueueSize      int      `json:"queue_size"`
	ActiveTasks    []string `json:"active_tasks"`
}

// AgentFederationState is the shared state passed through graph nodes during a
// federation run. Mirrors Python AgentState TypedDict.
type AgentFederationState struct {
	TaskTree             *TaskTree                  `json:"task_tree,omitempty"`
	CurrentNode          string                     `json:"current_node"`
	CompletedNodes       []string                   `json:"completed_nodes"`
	FailedNodes          []string                   `json:"failed_nodes"`
	ModulesInvolved      map[string]ModuleContext   `json:"modules_involved"`
	ActiveContracts      []Contract                 `json:"active_contracts"`
	Messages             []map[string]interface{}   `json:"messages"`
	Sender               string                     `json:"sender"`
	DebateState          *DebateState               `json:"debate_state,omitempty"`
	LintResults          map[string][]map[string]interface{} `json:"lint_results"`
	TestResults          map[string]map[string]interface{}   `json:"test_results"`
	InjectedPatterns     []ExperienceCard           `json:"injected_patterns"`
	InjectedAntipatterns []ExperienceCard           `json:"injected_antipatterns"`
	InjectedConstraints  []ExperienceCard           `json:"injected_constraints"`
	Decisions            []AuditRecord              `json:"decisions"`
	FinalStatus          FederationStatus           `json:"final_status"`
	ErrorBudgetConsumed  float64                    `json:"error_budget_consumed"`
}

// NewAgentFederationState creates an initialized federation state.
func NewAgentFederationState() AgentFederationState {
	return AgentFederationState{
		CompletedNodes:       []string{},
		FailedNodes:          []string{},
		ModulesInvolved:      map[string]ModuleContext{},
		ActiveContracts:      []Contract{},
		Messages:             []map[string]interface{}{},
		LintResults:          map[string][]map[string]interface{}{},
		TestResults:          map[string]map[string]interface{}{},
		InjectedPatterns:     []ExperienceCard{},
		InjectedAntipatterns: []ExperienceCard{},
		InjectedConstraints:  []ExperienceCard{},
		Decisions:            []AuditRecord{},
		FinalStatus:          FedPending,
	}
}

// ---------------------------------------------------------------------------
// Structured Output Schemas (from agents/schemas.py)
// ---------------------------------------------------------------------------

// TaskNode is a single node in the task tree (planner output).
type TaskNode struct {
	TaskID          string     `json:"task_id"`
	Title           string     `json:"title"`
	Description     string     `json:"description"`
	Module          string     `json:"module"`
	ChangeType      ChangeType `json:"change_type"`
	EstimatedLines  int        `json:"estimated_lines"`
	Dependencies    []string   `json:"dependencies"`
	ContractsNeeded []string   `json:"contracts_needed"`
}

// TaskEdge is a parent-child relationship in the task tree.
type TaskEdge struct {
	ParentID string   `json:"parent_id"`
	ChildIDs []string `json:"child_ids"`
}

// ContractProposal is a proposed interface contract (planner output).
type ContractProposal struct {
	FromModule    string                 `json:"from_module"`
	ToModule      string                 `json:"to_module"`
	Title         string                 `json:"title"`
	Description   string                 `json:"description"`
	InterfaceSpec map[string]interface{} `json:"interface_spec"`
}

// PlannerOutput is the structured output from the Planner agent.
type PlannerOutput struct {
	TaskTreeID      string             `json:"task_tree_id"`
	RootDescription string             `json:"root_description"`
	ModulesInvolved []string           `json:"modules_involved"`
	Nodes           []TaskNode         `json:"nodes"`
	Edges           []TaskEdge         `json:"edges"`
	Contracts       []ContractProposal `json:"contracts"`
	RiskAssessment  string             `json:"risk_assessment"` // low | medium | high
	Reasoning       string             `json:"reasoning"`
}

// ReviewVerdict is the structured output from Module Keeper review.
type ReviewVerdict struct {
	Approved            bool     `json:"approved"`
	Confidence          float64  `json:"confidence"`
	IssuesFound         []string `json:"issues_found"`
	ExperienceCardDrafts []string `json:"experience_card_drafts"`
	Suggestions         []string `json:"suggestions"`
	Reasoning           string   `json:"reasoning"`
}

// TechDebtItem is a single technical debt item found by Inspector.
type TechDebtItem struct {
	Location          string `json:"location"`
	Type              string `json:"type"` // code | design | test | docs | infrastructure
	Description       string `json:"description"`
	Severity          string `json:"severity"` // low | medium | high | critical
	EstimatedFixCost  string `json:"estimated_fix_cost"` // small | medium | large | xlarge
	DailyInterest     string `json:"daily_interest"`
	RecommendedAction string `json:"recommended_action"`
}

// InspectorReport is the structured output from Inspector agent.
type InspectorReport struct {
	ScanDate           string          `json:"scan_date"`
	ModulesScanned     []string        `json:"modules_scanned"`
	TechDebtItems      []TechDebtItem  `json:"tech_debt_items"`
	AntipatternsFound  []map[string]interface{} `json:"antipatterns_found"`
	ContractViolations []map[string]interface{} `json:"contract_violations"`
	OverallHealth      string          `json:"overall_health"` // healthy | concerning | critical
	Summary            string          `json:"summary"`
}

// ExperienceCardDraft is the structured output from Librarian.
type ExperienceCardDraft struct {
	Type       ExperienceType `json:"type"`
	Title      string         `json:"title"`
	Tags       []string       `json:"tags"`
	Module     string         `json:"module,omitempty"`
	Severity   Severity       `json:"severity"`
	Signature  string         `json:"signature"`
	Body       string         `json:"body"`
	Supersedes string         `json:"supersedes,omitempty"`
}

// ReviewResult captures the result of a single review submission.
type ReviewResult struct {
	ReviewID   string       `json:"review_id"`
	TaskID     string       `json:"task_id"`
	Module     string       `json:"module"`
	ReviewerID string       `json:"reviewer_id"`
	Status     ReviewStatus `json:"status"`
	Verdict    ReviewVerdict `json:"verdict"`
	CreatedAt  time.Time    `json:"created_at"`
	ResolvedAt *time.Time   `json:"resolved_at,omitempty"`
}

// NewReviewResult creates a review result with defaults.
func NewReviewResult(taskID, module, reviewerID string) ReviewResult {
	return ReviewResult{
		ReviewID:   newID("rev"),
		TaskID:     taskID,
		Module:     module,
		ReviewerID: reviewerID,
		Status:     ReviewPending,
		CreatedAt:  time.Now(),
	}
}
