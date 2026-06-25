// Package review manages the code review lifecycle in the Evergreen federation:
// submit → approve/reject/request_changes → merge.
//
// Ported from src/governance/review.py.
package review

import (
	"sync"
	"time"

	"reasonix_gr/internal/evergreen/types"
)

// Gate manages code review submissions, approvals, and rejections.
type Gate struct {
	mu       sync.RWMutex
	reviews  map[string]*types.ReviewResult // reviewID → result
	byTask   map[string][]string            // taskID → reviewIDs
}

// NewGate creates a review gate.
func NewGate() *Gate {
	return &Gate{
		reviews: make(map[string]*types.ReviewResult),
		byTask:  make(map[string][]string),
	}
}

// Submit creates a new review submission.
func (g *Gate) Submit(taskID, module, reviewerID string) *types.ReviewResult {
	r := types.NewReviewResult(taskID, module, reviewerID)

	g.mu.Lock()
	g.reviews[r.ReviewID] = &r
	g.byTask[taskID] = append(g.byTask[taskID], r.ReviewID)
	g.mu.Unlock()

	return &r
}

// Approve marks a review as approved.
func (g *Gate) Approve(reviewID string, verdict types.ReviewVerdict) *types.ReviewResult {
	g.mu.Lock()
	defer g.mu.Unlock()

	r := g.reviews[reviewID]
	if r == nil {
		return nil
	}
	r.Status = types.ReviewApproved
	r.Verdict = verdict
	now := time.Now()
	r.ResolvedAt = &now
	return r
}

// Reject marks a review as rejected.
func (g *Gate) Reject(reviewID string, verdict types.ReviewVerdict) *types.ReviewResult {
	g.mu.Lock()
	defer g.mu.Unlock()

	r := g.reviews[reviewID]
	if r == nil {
		return nil
	}
	r.Status = types.ReviewRejected
	r.Verdict = verdict
	now := time.Now()
	r.ResolvedAt = &now
	return r
}

// RequestChanges marks a review as needing changes.
func (g *Gate) RequestChanges(reviewID string, verdict types.ReviewVerdict) *types.ReviewResult {
	g.mu.Lock()
	defer g.mu.Unlock()

	r := g.reviews[reviewID]
	if r == nil {
		return nil
	}
	r.Status = types.ReviewChangesRequested
	r.Verdict = verdict
	return r
}

// Status returns a review's current status.
func (g *Gate) Status(reviewID string) types.ReviewStatus {
	g.mu.RLock()
	defer g.mu.RUnlock()

	r := g.reviews[reviewID]
	if r == nil {
		return ""
	}
	return r.Status
}

// PendingCount returns the number of pending reviews.
func (g *Gate) PendingCount() int {
	g.mu.RLock()
	defer g.mu.RUnlock()

	count := 0
	for _, r := range g.reviews {
		if r.Status == types.ReviewPending {
			count++
		}
	}
	return count
}

// CanMerge checks whether all reviews for a task are approved.
func (g *Gate) CanMerge(taskID string) bool {
	g.mu.RLock()
	defer g.mu.RUnlock()

	reviewIDs := g.byTask[taskID]
	if len(reviewIDs) == 0 {
		return true // no reviews needed
	}

	for _, rid := range reviewIDs {
		r := g.reviews[rid]
		if r == nil || r.Status != types.ReviewApproved {
			return false
		}
	}
	return true
}

// ForTask returns all reviews for a task.
func (g *Gate) ForTask(taskID string) []*types.ReviewResult {
	g.mu.RLock()
	defer g.mu.RUnlock()

	var out []*types.ReviewResult
	for _, rid := range g.byTask[taskID] {
		if r := g.reviews[rid]; r != nil {
			out = append(out, r)
		}
	}
	return out
}

// Get returns a review by ID.
func (g *Gate) Get(reviewID string) *types.ReviewResult {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.reviews[reviewID]
}
