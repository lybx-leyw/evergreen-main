// Package audit provides decision audit logging for the Evergreen federation.
// Every agent decision is recorded as an immutable JSONL entry, one file per
// agent per day. The logger also implements event.Sink to auto-record
// high-signal federation events.
//
// Ported from src/core/audit.py.
package audit

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/types"
)

// Logger records agent decisions as JSONL files.
// Thread-safe via sync.Mutex.
type Logger struct {
	mu      sync.Mutex
	dataDir string
	files   map[string]*os.File // key: "agentID_YYYY-MM-DD"
}

// NewLogger creates an audit logger. dataDir is the directory for audit files.
func NewLogger(dataDir string) (*Logger, error) {
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("audit: create data dir: %w", err)
	}
	return &Logger{
		dataDir: dataDir,
		files:   make(map[string]*os.File),
	}, nil
}

// Record writes an audit record to the appropriate daily file.
func (l *Logger) Record(r types.AuditRecord) error {
	l.mu.Lock()
	defer l.mu.Unlock()

	day := r.Timestamp.Format("2006-01-02")
	key := r.AgentID + "_" + day

	f, ok := l.files[key]
	if !ok {
		filename := filepath.Join(l.dataDir, fmt.Sprintf("%s_%s.jsonl", r.AgentID, day))
		var err error
		f, err = os.OpenFile(filename, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
		if err != nil {
			return fmt.Errorf("audit: open file: %w", err)
		}
		l.files[key] = f
	}

	data, err := json.Marshal(r)
	if err != nil {
		return fmt.Errorf("audit: marshal record: %w", err)
	}
	data = append(data, '\n')

	if _, err := f.Write(data); err != nil {
		return fmt.Errorf("audit: write record: %w", err)
	}

	return nil
}

// Query returns audit records matching the given filters.
// Zero/empty filters match everything.
func (l *Logger) Query(agentID, decisionType, module string) ([]types.AuditRecord, error) {
	l.mu.Lock()
	defer l.mu.Unlock()

	var results []types.AuditRecord

	entries, err := os.ReadDir(l.dataDir)
	if err != nil {
		return nil, fmt.Errorf("audit: read data dir: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".jsonl") {
			continue
		}

		if agentID != "" && !strings.HasPrefix(entry.Name(), agentID+"_") {
			continue
		}

		data, err := os.ReadFile(filepath.Join(l.dataDir, entry.Name()))
		if err != nil {
			continue
		}

		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			if line == "" {
				continue
			}
			var r types.AuditRecord
			if err := json.Unmarshal([]byte(line), &r); err != nil {
				continue
			}
			if decisionType != "" && r.DecisionType != decisionType {
				continue
			}
			if module != "" && r.Context.Module != module {
				continue
			}
			results = append(results, r)
		}
	}

	return results, nil
}

// Close flushes and closes all open audit files.
func (l *Logger) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()

	for key, f := range l.files {
		if err := f.Close(); err != nil {
			return fmt.Errorf("audit: close %s: %w", key, err)
		}
	}
	l.files = make(map[string]*os.File)
	return nil
}

// ---------------------------------------------------------------------------
// event.Sink implementation — auto-record high-signal events
// ---------------------------------------------------------------------------

// Emit implements event.Sink. It records high-signal federation events
// (task completion, contract acceptance, experience approval, credit changes,
// review decisions) as audit records automatically.
func (l *Logger) Emit(e event.Event) {
	switch e.Kind {
	case event.TaskCompleted, event.TaskFailed:
		if e.Federation != nil && e.Federation.Task != nil {
			t := e.Federation.Task
			dt := "task_completed"
			outcome := "success"
			if e.Kind == event.TaskFailed {
				dt = "task_failed"
				outcome = "failed"
			}
			r := types.NewAuditRecord(t.AgentID, types.RoleTaskExecutor, dt)
			r.Context.TaskID = t.TaskID
			r.Context.Module = t.Module
			r.Outcome = outcome
			r.Decision = t.Title
			_ = l.Record(r)
		}

	case event.ContractAccepted, event.ContractRejected, event.ContractViolated:
		if e.Federation != nil && e.Federation.Contract != nil {
			c := e.Federation.Contract
			dt := "contract_accepted"
			switch e.Kind {
			case event.ContractRejected:
				dt = "contract_rejected"
			case event.ContractViolated:
				dt = "contract_violated"
			}
			r := types.NewAuditRecord("federation", types.RolePlanner, dt)
			r.Context.ContractsReferenced = []string{c.ContractID}
			r.Decision = c.Title
			_ = l.Record(r)
		}

	case event.ExperienceApproved:
		if e.Federation != nil && e.Federation.Experience != nil {
			exp := e.Federation.Experience
			r := types.NewAuditRecord("librarian", types.RoleLibrarian, "experience_approved")
			r.Context.ExperienceCardsConsulted = []string{exp.CardID}
			r.Decision = exp.Title
			_ = l.Record(r)
		}

	case event.CreditChanged:
		if e.Federation != nil && e.Federation.Credit != nil {
			c := e.Federation.Credit
			r := types.NewAuditRecord(c.AgentID, types.RolePlanner, "credit_changed")
			r.Decision = fmt.Sprintf("%s: %+.1f → %.1f", c.Dimension, c.Delta, c.NewScore)
			_ = l.Record(r)
		}

	case event.ReviewApproved, event.ReviewRejected:
		if e.Federation != nil && e.Federation.Review != nil {
			rev := e.Federation.Review
			dt := "review_approved"
			if e.Kind == event.ReviewRejected {
				dt = "review_rejected"
			}
			r := types.NewAuditRecord(rev.ReviewerID, types.RoleModuleKeeper, dt)
			r.Context.TaskID = rev.TaskID
			r.Context.Module = rev.Module
			r.Decision = rev.Reasoning
			_ = l.Record(r)
		}
	}
}
