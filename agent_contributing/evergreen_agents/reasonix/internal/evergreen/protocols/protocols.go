// Package protocols defines engineering protocols enforced by the Evergreen
// federation: branching rules, commit message format, test coverage gates,
// and merge queue management.
//
// Ported from src/protocols/branching.py + testing.py.
package protocols

import (
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// Branching Protocol
// ---------------------------------------------------------------------------

// CLValidationResult reports the outcome of a change-list size check.
type CLValidationResult struct {
	Valid       bool
	LinesChanged int
	MaxAllowed   int
	Severity     string // ok | warning | blocking
	Message      string
}

// ValidateCLSize checks whether a change is within acceptable size limits.
// Ideal: <100 lines. Warning: 100-300. Blocking: >300. (蓝图 A.2)
func ValidateCLSize(linesChanged int) CLValidationResult {
	r := CLValidationResult{LinesChanged: linesChanged}
	switch {
	case linesChanged < 100:
		r.Valid = true
		r.Severity = "ok"
		r.Message = "CL size within ideal range"
	case linesChanged <= 300:
		r.Valid = true
		r.Severity = "warning"
		r.Message = fmt.Sprintf("CL size %d exceeds ideal range (<100); consider splitting", linesChanged)
	default:
		r.Valid = false
		r.Severity = "blocking"
		r.Message = fmt.Sprintf("CL size %d exceeds max allowed (300); must be split into smaller changes", linesChanged)
	}
	r.MaxAllowed = 300
	return r
}

// conventionalCommitRE matches Conventional Commits format.
var conventionalCommitRE = regexp.MustCompile(`^(feat|fix|refactor|test|docs|chore|perf|style|ci|build|revert)(\(.+\))?(!)?: .+`)

// ValidateCommitMessage checks whether a commit message follows Conventional Commits.
func ValidateCommitMessage(msg string) (bool, string) {
	msg = strings.TrimSpace(msg)
	if msg == "" {
		return false, "commit message is empty"
	}
	if !conventionalCommitRE.MatchString(msg) {
		return false, "commit message must follow format: type(scope): description (e.g., feat(auth): add login)"
	}
	return true, ""
}

// ---------------------------------------------------------------------------
// Merge Queue
// ---------------------------------------------------------------------------

// MergeQueueEntry represents a change waiting in the merge queue.
type MergeQueueEntry struct {
	TaskID    string
	Module    string
	Branch    string
	EnqueuedAt time.Time
	CIStatus  string // pending | running | passed | failed
}

// MergeQueue manages serialized, CI-gated merging.
type MergeQueue struct {
	mu         sync.Mutex
	entries    []*MergeQueueEntry
	batchSize  int
	ciTimeout  time.Duration
	autoRevert bool
}

// NewMergeQueue creates a merge queue.
func NewMergeQueue(batchSize int, ciTimeout time.Duration, autoRevert bool) *MergeQueue {
	if batchSize <= 0 {
		batchSize = 5
	}
	if ciTimeout <= 0 {
		ciTimeout = 30 * time.Minute
	}
	return &MergeQueue{
		batchSize:  batchSize,
		ciTimeout:  ciTimeout,
		autoRevert: autoRevert,
	}
}

// Enqueue adds a task to the merge queue.
func (mq *MergeQueue) Enqueue(taskID, module, branch string) *MergeQueueEntry {
	mq.mu.Lock()
	defer mq.mu.Unlock()

	entry := &MergeQueueEntry{
		TaskID:     taskID,
		Module:     module,
		Branch:     branch,
		EnqueuedAt: time.Now(),
		CIStatus:   "pending",
	}
	mq.entries = append(mq.entries, entry)
	return entry
}

// Dequeue removes and returns the next batch of entries ready for CI.
func (mq *MergeQueue) Dequeue() []*MergeQueueEntry {
	mq.mu.Lock()
	defer mq.mu.Unlock()

	n := mq.batchSize
	if n > len(mq.entries) {
		n = len(mq.entries)
	}
	batch := mq.entries[:n]
	mq.entries = mq.entries[n:]
	return batch
}

// CIPass marks a batch as CI-passed.
func (mq *MergeQueue) CIPass(batch []*MergeQueueEntry) {
	for _, e := range batch {
		e.CIStatus = "passed"
	}
}

// CIFail marks a batch as CI-failed.
func (mq *MergeQueue) CIFail(batch []*MergeQueueEntry) {
	for _, e := range batch {
		e.CIStatus = "failed"
	}
}

// Length returns the current queue depth.
func (mq *MergeQueue) Length() int {
	mq.mu.Lock()
	defer mq.mu.Unlock()
	return len(mq.entries)
}

// ---------------------------------------------------------------------------
// Testing Protocol
// ---------------------------------------------------------------------------

// CoverageGateResult reports test coverage validation.
type CoverageGateResult struct {
	Passed          bool
	BranchCoverage  float64
	MinCoverage     float64
	SmallTestPct    float64 // percentage of tests that are small/unit
	FlakyTests      []string
	Message         string
}

// ValidateCoverage checks test coverage against the pyramid standards.
// Requirements: branch coverage >= 80%, small tests >= 70% of total.
func ValidateCoverage(branchCoverage, smallTestPct float64, totalTests, smallTests int) CoverageGateResult {
	r := CoverageGateResult{
		BranchCoverage: branchCoverage,
		MinCoverage:    0.80,
		SmallTestPct:   smallTestPct,
		Passed:         true,
	}

	var issues []string

	if branchCoverage < 0.80 {
		r.Passed = false
		issues = append(issues, fmt.Sprintf("branch coverage %.1f%% below 80%% minimum", branchCoverage*100))
	}

	if totalTests > 0 && smallTestPct < 0.70 {
		r.Passed = false
		issues = append(issues, fmt.Sprintf("small tests %.1f%% below 70%% minimum (test pyramid)", smallTestPct*100))
	}

	if r.Passed {
		r.Message = fmt.Sprintf("Coverage OK: branch %.1f%%, small tests %.1f%%", branchCoverage*100, smallTestPct*100)
	} else {
		r.Message = strings.Join(issues, "; ")
	}
	return r
}

// TestSize classifies a test by size.
type TestSize string

const (
	TestSmall  TestSize = "small"  // unit test, no I/O, <100ms
	TestMedium TestSize = "medium" // integration, local I/O, <1s
	TestLarge  TestSize = "large"  // e2e, network, >1s
)

// ClassifyTest determines test size from its characteristics.
func ClassifyTest(name string, durationMs int64) TestSize {
	if durationMs < 100 {
		return TestSmall
	}
	if durationMs < 1000 {
		return TestMedium
	}
	return TestLarge
}
