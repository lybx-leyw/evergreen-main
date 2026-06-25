// Package credit provides the credit scoring engine for the Evergreen federation.
package credit

import (
	"testing"

	"reasonix_gr/internal/evergreen/types"
)

func TestNewEngine(t *testing.T) {
	e := NewEngine(nil)
	if e == nil {
		t.Fatal("NewEngine returned nil")
	}
	if len(e.scores) != 0 {
		t.Errorf("scores len = %d, want 0", len(e.scores))
	}
}

func TestRegister(t *testing.T) {
	e := NewEngine(nil)
	cs := e.Register("eva-001", types.RoleTaskExecutor)
	if cs == nil {
		t.Fatal("Register returned nil")
	}
	if cs.AgentID != "eva-001" {
		t.Errorf("AgentID = %s, want eva-001", cs.AgentID)
	}
	if cs.Composite != 100.0 {
		t.Errorf("Composite = %.1f, want 100.0", cs.Composite)
	}
}

func TestGet(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RolePlanner)

	cs := e.Get("eva-001")
	if cs == nil {
		t.Fatal("Get returned nil")
	}
	if cs.Role != types.RolePlanner {
		t.Errorf("Role = %s, want planner", cs.Role)
	}

	if cs := e.Get("nonexistent"); cs != nil {
		t.Error("Get for nonexistent agent should return nil")
	}
}

func TestApplyDelta(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RoleTaskExecutor)

	// Positive delta
	cs := e.ApplyDelta("eva-001", "code_quality", -10.0)
	if cs == nil {
		t.Fatal("ApplyDelta returned nil")
	}
	if cs.CodeQuality != 90.0 {
		t.Errorf("CodeQuality = %.1f, want 90.0", cs.CodeQuality)
	}
	if cs.Composite == 100.0 {
		t.Error("Composite should have changed after delta")
	}

	// Clamp below 0
	e.ApplyDelta("eva-001", "code_quality", -100.0)
	cs = e.Get("eva-001")
	if cs.CodeQuality < 0.0 {
		t.Errorf("CodeQuality = %.2f, should be clamped >= 0", cs.CodeQuality)
	}

	// Clamp above 100
	e.ApplyDelta("eva-001", "code_quality", 200.0)
	cs = e.Get("eva-001")
	if cs.CodeQuality > 100.0 {
		t.Errorf("CodeQuality = %.2f, should be clamped <= 100", cs.CodeQuality)
	}

	// Nonexistent agent
	if cs := e.ApplyDelta("nobody", "code_quality", 5.0); cs != nil {
		t.Error("ApplyDelta for nonexistent agent should return nil")
	}
}

func TestOnTaskCompleted(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RoleTaskExecutor)

	// Successful task with lint pass and good coverage
	cs := e.OnTaskCompleted("eva-001", true, true, 0.85, true)
	if cs == nil {
		t.Fatal("OnTaskCompleted returned nil")
	}
	if cs.TotalTasks != 1 {
		t.Errorf("TotalTasks = %d, want 1", cs.TotalTasks)
	}
	if cs.TotalApprovals != 1 {
		t.Errorf("TotalApprovals = %d, want 1", cs.TotalApprovals)
	}
	if cs.CodeQuality >= 100.0 {
		t.Logf("CodeQuality after success+lint at initial 100: %.1f (clamped at 100)", cs.CodeQuality)
	}

	// Failed task
	cs2 := e.OnTaskCompleted("eva-001", false, false, 0.5, false)
	if cs2.TotalTasks != 2 {
		t.Errorf("TotalTasks = %d, want 2", cs2.TotalTasks)
	}
	if cs2.TotalRejections != 1 {
		t.Errorf("TotalRejections = %d, want 1", cs2.TotalRejections)
	}
}

func TestOnReviewResult(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RoleModuleKeeper)

	// First tank the score so a positive delta is visible
	e.ApplyDelta("eva-001", "review_accuracy", -20.0)
	cs := e.OnReviewResult("eva-001", true)
	if cs.ReviewAccuracy != 83.0 {
		t.Errorf("ReviewAccuracy = %.1f, want 83.0 (80 + 3)", cs.ReviewAccuracy)
	}

	e.OnReviewResult("eva-001", false)
	cs = e.Get("eva-001")
	if cs.ReviewAccuracy != 75.0 {
		t.Errorf("ReviewAccuracy = %.1f, want 75.0 (83 - 8)", cs.ReviewAccuracy)
	}

	// Verify clamping — cannot go above 100
	for i := 0; i < 10; i++ {
		e.OnReviewResult("eva-001", true)
	}
	cs = e.Get("eva-001")
	if cs.ReviewAccuracy > 100.0 {
		t.Errorf("ReviewAccuracy = %.1f, should be clamped <= 100", cs.ReviewAccuracy)
	}
}

func TestOnExperienceApproved(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RoleLibrarian)

	// Tank first so delta is visible
	e.ApplyDelta("eva-001", "experience_quality", -20.0)
	cs := e.OnExperienceApproved("eva-001", true)
	if cs.ExperienceQuality != 85.0 {
		t.Errorf("ExperienceQuality = %.1f, want 85.0 (80 + 5)", cs.ExperienceQuality)
	}

	e.OnExperienceApproved("eva-001", false)
	cs = e.Get("eva-001")
	if cs.ExperienceQuality != 83.0 {
		t.Errorf("ExperienceQuality = %.1f, want 83.0 (85 - 2)", cs.ExperienceQuality)
	}
}

func TestOnErrorBudgetBust(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RoleTaskExecutor)

	cs := e.OnErrorBudgetBust("eva-001", 15.0)
	if cs.ErrorBudgetRespect != 85.0 {
		t.Errorf("ErrorBudgetRespect = %.1f, want 85.0", cs.ErrorBudgetRespect)
	}
}

func TestCanExecute(t *testing.T) {
	e := NewEngine(nil)
	e.Register("eva-001", types.RoleTaskExecutor)

	if !e.CanExecute("eva-001", 50.0) {
		t.Error("CanExecute should return true for high-score agent")
	}

	// Tank all dimensions to bring composite below 50
	dims := []string{"code_quality", "test_quality", "review_accuracy", "experience_quality", "error_budget_respect", "collaboration"}
	for _, dim := range dims {
		for i := 0; i < 6; i++ {
			e.ApplyDelta("eva-001", dim, -10.0)
		}
	}

	if e.CanExecute("eva-001", 50.0) {
		cs := e.Get("eva-001")
		t.Errorf("CanExecute should return false for low-score agent (composite=%.1f)", cs.Composite)
	}

	if e.CanExecute("nobody", 50.0) {
		t.Error("CanExecute should return false for nonexistent agent")
	}
}

func TestLowestScoring(t *testing.T) {
	e := NewEngine(nil)

	// Register agents with different scores
	for i, id := range []string{"a", "b", "c", "d", "e"} {
		cs := e.Register(id, types.RoleTaskExecutor)
		// Manually adjust scores
		for j := 0; j < i*5; j++ {
			e.ApplyDelta(id, "code_quality", -1.0)
		}
		_ = cs
	}

	lowest := e.LowestScoring(3)
	if len(lowest) != 3 {
		t.Errorf("LowestScoring len = %d, want 3", len(lowest))
	}
	// Verify ascending order
	for i := 1; i < len(lowest); i++ {
		if lowest[i].Composite < lowest[i-1].Composite {
			t.Errorf("LowestScoring not sorted: index %d (%.1f) < index %d (%.1f)",
				i, lowest[i].Composite, i-1, lowest[i-1].Composite)
		}
	}
}

func TestListAll(t *testing.T) {
	e := NewEngine(nil)
	e.Register("a", types.RolePlanner)
	e.Register("b", types.RoleModuleKeeper)

	all := e.ListAll()
	if len(all) != 2 {
		t.Errorf("ListAll len = %d, want 2", len(all))
	}
}
