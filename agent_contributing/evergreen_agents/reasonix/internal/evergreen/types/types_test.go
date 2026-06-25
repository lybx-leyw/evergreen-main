package types

import (
	"testing"
	"time"
)

func TestValidAgentRole(t *testing.T) {
	tests := []struct {
		input string
		want  AgentRole
		ok    bool
	}{
		{"planner", RolePlanner, true},
		{"module_keeper", RoleModuleKeeper, true},
		{"task_executor", RoleTaskExecutor, true},
		{"inspector", RoleInspector, true},
		{"librarian", RoleLibrarian, true},
		{"unknown", "", false},
		{"", "", false},
	}
	for _, tt := range tests {
		got, ok := ValidAgentRole(tt.input)
		if ok != tt.ok || got != tt.want {
			t.Errorf("ValidAgentRole(%q) = (%q, %v), want (%q, %v)", tt.input, got, ok, tt.want, tt.ok)
		}
	}
}

func TestTaskStatus_IsTerminal(t *testing.T) {
	terminal := []TaskStatus{TaskCompleted, TaskFailed, TaskRejected}
	nonTerminal := []TaskStatus{TaskPending, TaskPlanning, TaskContracting, TaskAssigned, TaskInProgress, TaskInReview, TaskInMergeQ, TaskBlocked}

	for _, s := range terminal {
		if !s.IsTerminal() {
			t.Errorf("%s.IsTerminal() = false, want true", s)
		}
	}
	for _, s := range nonTerminal {
		if s.IsTerminal() {
			t.Errorf("%s.IsTerminal() = true, want false", s)
		}
	}
}

func TestNewAgentIdentity(t *testing.T) {
	id := NewAgentIdentity(RolePlanner, "Test Planner")
	if id.AgentID == "" {
		t.Error("AgentID is empty")
	}
	if id.Role != RolePlanner {
		t.Errorf("Role = %s, want planner", id.Role)
	}
	if id.Status != AgentIdle {
		t.Errorf("Status = %s, want idle", id.Status)
	}
	if err := id.Validate(); err != nil {
		t.Errorf("Validate() error = %v", err)
	}
}

func TestAgentIdentity_Validate(t *testing.T) {
	id := AgentIdentity{Role: "invalid"}
	if err := id.Validate(); err == nil {
		t.Error("expected error for empty agent_id and invalid role")
	}
}

func TestNewTaskSpec(t *testing.T) {
	ts := NewTaskSpec("Add login", "Add login button", "auth", ChangeFeat)
	if ts.TaskID == "" {
		t.Error("TaskID is empty")
	}
	if ts.Status != TaskPending {
		t.Errorf("Status = %s, want pending", ts.Status)
	}
	if ts.EstimatedLines != 50 {
		t.Errorf("EstimatedLines = %d, want 50", ts.EstimatedLines)
	}
	if err := ts.Validate(); err != nil {
		t.Errorf("Validate() error = %v", err)
	}
}

func TestNewTaskTree(t *testing.T) {
	tt := NewTaskTree("Fix login bug", "task-root")
	if tt.TreeID == "" {
		t.Error("TreeID is empty")
	}
	if tt.Status != "active" {
		t.Errorf("Status = %s, want active", tt.Status)
	}
	if len(tt.Nodes) != 0 {
		t.Errorf("Nodes len = %d, want 0", len(tt.Nodes))
	}
}

func TestNewContract(t *testing.T) {
	c := NewContract("auth", "courses", "Auth API", "Login endpoint", nil)
	if c.ContractID == "" {
		t.Error("ContractID is empty")
	}
	if c.Status != ContractProposed {
		t.Errorf("Status = %s, want proposed", c.Status)
	}
	if c.FromModule != "auth" || c.ToModule != "courses" {
		t.Error("module fields mismatch")
	}
}

func TestNewExperienceCard(t *testing.T) {
	c := NewExperienceCard(ExpPattern, "Cache-first architecture")
	if c.ID == "" {
		t.Error("ID is empty")
	}
	if c.Status != CardProposed {
		t.Errorf("Status = %s, want proposed", c.Status)
	}
	if c.Version != 1 {
		t.Errorf("Version = %d, want 1", c.Version)
	}
}

func TestExperienceCard_ToMarkdown(t *testing.T) {
	c := ExperienceCard{
		ID:          "exp-abc",
		Type:        ExpPattern,
		Title:       "Test Pattern",
		Tags:        []string{"cache", "performance"},
		CreatedDate: time.Now().Format("2006-01-02"),
		Module:      "core_storage",
		Severity:    SevInfo,
		Status:      CardApproved,
		Version:     1,
		Body:        "Use a cache-first strategy for API calls.",
	}
	md := c.ToMarkdown()
	if md == "" {
		t.Error("ToMarkdown returned empty string")
	}
	// Verify key fields are present
	for _, want := range []string{"exp-abc", "pattern", "Test Pattern", "cache", "performance", "cache-first"} {
		if !contains(md, want) {
			t.Errorf("ToMarkdown missing expected content: %q", want)
		}
	}
}

func TestFromMarkdown(t *testing.T) {
	md := `---
type: pattern
title: Cache-First Architecture
tags: [cache, performance]
date: 2025-06-15
module: core_storage
severity: info
status: approved
version: 1
---
Use a cache-first strategy.`

	c := FromMarkdown(md, "2025-06-15-cache-first-architecture.md")
	if c.Type != ExpPattern {
		t.Errorf("Type = %s, want pattern", c.Type)
	}
	if c.Title != "Cache-First Architecture" {
		t.Errorf("Title = %s, want Cache-First Architecture", c.Title)
	}
	if c.Module != "core_storage" {
		t.Errorf("Module = %s, want core_storage", c.Module)
	}
	if c.Status != CardApproved {
		t.Errorf("Status = %s, want approved", c.Status)
	}
	if len(c.Tags) != 2 {
		t.Errorf("Tags len = %d, want 2", len(c.Tags))
	}
}

func TestFromMarkdown_Legacy(t *testing.T) {
	md := `---
task_type: bug-fix
tags: [palace, overflow]
date: 2025-06-10
outcome: success
---
Fixed text overflow in Palace detail view.`

	c := FromMarkdown(md, "2025-06-10-ui-overflow-fix.md")
	if c.Type != ExpAntipattern {
		t.Errorf("Type = %s, want antipattern", c.Type)
	}
	if c.Status != CardApproved {
		t.Errorf("Status = %s, want approved", c.Status)
	}
	if c.Body != "Fixed text overflow in Palace detail view." {
		t.Errorf("Body = %q, want original body", c.Body)
	}
}

func TestCreditScore_Tier(t *testing.T) {
	tests := []struct {
		composite float64
		tier      CreditTier
	}{
		{95, TierExcellent},
		{90, TierExcellent},
		{80, TierGood},
		{75, TierGood},
		{65, TierWarning},
		{60, TierWarning},
		{50, TierProbation},
		{40, TierProbation},
		{30, TierSuspended},
	}
	for _, tt := range tests {
		cs := CreditScore{Composite: tt.composite}
		if cs.Tier() != tt.tier {
			t.Errorf("Composite=%.0f Tier() = %s, want %s", tt.composite, cs.Tier(), tt.tier)
		}
	}
}

func TestNewCreditScore(t *testing.T) {
	cs := NewCreditScore("eva-abc", RoleTaskExecutor)
	if cs.Composite != 100.0 {
		t.Errorf("Composite = %.1f, want 100.0", cs.Composite)
	}
	if cs.CodeQuality != 100.0 {
		t.Errorf("CodeQuality = %.1f, want 100.0", cs.CodeQuality)
	}
}

func TestNewAuditRecord(t *testing.T) {
	r := NewAuditRecord("eva-abc", RolePlanner, "task_decomposition")
	if r.ID == "" {
		t.Error("ID is empty")
	}
	if r.AgentRole != RolePlanner {
		t.Errorf("AgentRole = %s, want planner", r.AgentRole)
	}
	jsonl := r.ToJSONL()
	if jsonl == "" {
		t.Error("ToJSONL returned empty string")
	}
}

func TestNewAgentFederationState(t *testing.T) {
	s := NewAgentFederationState()
	if s.FinalStatus != FedPending {
		t.Errorf("FinalStatus = %s, want pending", s.FinalStatus)
	}
	if s.ErrorBudgetConsumed != 0 {
		t.Errorf("ErrorBudgetConsumed = %f, want 0", s.ErrorBudgetConsumed)
	}
}

func TestNewReviewResult(t *testing.T) {
	r := NewReviewResult("task-abc", "auth", "eva-keeper")
	if r.ReviewID == "" {
		t.Error("ReviewID is empty")
	}
	if r.Status != ReviewPending {
		t.Errorf("Status = %s, want pending", r.Status)
	}
}

func TestFederationStatus_Values(t *testing.T) {
	if FedPending != "pending" {
		t.Errorf("FedPending = %q, want pending", FedPending)
	}
	if FedSuccess != "success" {
		t.Errorf("FedSuccess = %q, want success", FedSuccess)
	}
}

func contains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
