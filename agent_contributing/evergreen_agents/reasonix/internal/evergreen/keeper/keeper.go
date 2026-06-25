// Package keeper implements the Module Keeper agent — the code-review authority
// for a single module. Keepers review incoming changes, manage the task queue,
// enforce contracts, and curate experience drafts. They use the quick-thinking
// LLM tier.
//
// Ported from src/agents/keeper.py.
package keeper

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"reasonix_gr/internal/agent"
	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/contracts"
	"reasonix_gr/internal/evergreen/experience"
	"reasonix_gr/internal/evergreen/review"
	"reasonix_gr/internal/evergreen/types"
	"reasonix_gr/internal/provider"
	"reasonix_gr/internal/tool"
)

// Keeper is the Module Keeper agent. It implements agent.Runner.
type Keeper struct {
	identity   types.AgentIdentity
	prov       provider.Provider
	registry   *tool.Registry
	session    *agent.Session
	sink       event.Sink
	store      *experience.Store
	reviews    *review.Gate
	contracts  *contracts.Model
	taskQueue  []types.TaskSpec
}

// New creates a Module Keeper agent.
func New(
	identity types.AgentIdentity,
	prov provider.Provider,
	registry *tool.Registry,
	session *agent.Session,
	sink event.Sink,
	store *experience.Store,
	reviews *review.Gate,
	contracts *contracts.Model,
) *Keeper {
	return &Keeper{
		identity:  identity,
		prov:      prov,
		registry:  registry,
		session:   session,
		sink:      sink,
		store:     store,
		reviews:   reviews,
		contracts: contracts,
		taskQueue: []types.TaskSpec{},
	}
}

// Identity returns the keeper's agent identity.
func (k *Keeper) Identity() types.AgentIdentity { return k.identity }

// Run implements agent.Runner. It processes incoming review requests and
// task queue management commands.
func (k *Keeper) Run(ctx context.Context, input string) error {
	// Emit federation phase event
	k.sink.Emit(event.Event{
		Kind: event.Phase,
		Text: fmt.Sprintf("keeper · %s", k.identity.Module),
		Federation: &event.FederationPayload{
			System: &event.FederationSystem{
				Module:  k.identity.Module,
				AgentID: k.identity.AgentID,
			},
		},
	})

	// Determine if this is a review request
	if strings.Contains(input, "review:") || strings.Contains(input, "REVIEW:") {
		return k.handleReview(ctx, input)
	}

	// Or a task queue operation
	if strings.Contains(input, "queue:") || strings.Contains(input, "QUEUE:") {
		return k.handleQueue(ctx, input)
	}

	return nil
}

// handleReview processes a code review request using the LLM.
func (k *Keeper) handleReview(ctx context.Context, input string) error {
	taskID := k.extractField(input, "task_id")

	// Load relevant experiences for review context
	patterns, antipatterns, constraints := k.store.InjectForTask(k.identity.Module, input)

	// Build review prompt
	prompt := k.buildReviewPrompt(input, patterns, antipatterns, constraints)

	// Append to session
	k.session.Add(provider.Message{Role: "user", Content: prompt})

	// Call LLM
	req := provider.Request{
		Messages:    k.session.Messages,
		Tools:       k.registry.Schemas(),
		Temperature: 0.3,
		MaxTokens:   4096,
	}

	stream, err := k.prov.Stream(ctx, req)
	if err != nil {
		k.sink.Emit(event.Event{Kind: event.TurnDone, Err: err})
		return err
	}

	// Collect response
	var fullText strings.Builder
	for chunk := range stream {
		if chunk.Text != "" {
			fullText.WriteString(chunk.Text)
			k.sink.Emit(event.Event{Kind: event.Text, Text: chunk.Text})
		}
	}

	// Parse review verdict from LLM output
	verdict := k.parseReviewVerdict(fullText.String())

	// Submit review
	result := k.reviews.Submit(taskID, k.identity.Module, k.identity.AgentID)

	if verdict.Approved {
		k.reviews.Approve(result.ReviewID, verdict)
		k.sink.Emit(event.Event{
			Kind: event.ReviewApproved,
			Federation: &event.FederationPayload{
				Review: &event.FederationReview{
					ReviewID:   result.ReviewID,
					TaskID:     taskID,
					Module:     k.identity.Module,
					ReviewerID: k.identity.AgentID,
					Approved:   true,
					Reasoning:  verdict.Reasoning,
				},
			},
		})
	} else {
		k.reviews.Reject(result.ReviewID, verdict)
		k.sink.Emit(event.Event{
			Kind: event.ReviewRejected,
			Federation: &event.FederationPayload{
				Review: &event.FederationReview{
					ReviewID:   result.ReviewID,
					TaskID:     taskID,
					Module:     k.identity.Module,
					ReviewerID: k.identity.AgentID,
					Approved:   false,
					Reasoning:  verdict.Reasoning,
				},
			},
		})
	}

	k.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// handleQueue manages the task queue.
func (k *Keeper) handleQueue(ctx context.Context, input string) error {
	// Enqueue tasks, assign priorities, etc.
	// TODO: full LLM-driven queue management
	k.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// buildReviewPrompt constructs the LLM prompt for code review.
func (k *Keeper) buildReviewPrompt(code string, patterns, antipatterns, constraints []*types.ExperienceCard) string {
	var sb strings.Builder
	sb.WriteString("You are a Module Keeper agent responsible for code review.\n\n")
	sb.WriteString("## Your Role\n")
	sb.WriteString(fmt.Sprintf("- Module: %s\n", k.identity.Module))
	sb.WriteString("- You have OWNERS authority for this module.\n")
	sb.WriteString("- Review the following change for correctness, safety, and adherence to patterns.\n\n")

	if len(constraints) > 0 {
		sb.WriteString("## Hard Constraints (must be followed)\n")
		for _, c := range constraints {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", c.Title, c.Body))
		}
		sb.WriteString("\n")
	}

	if len(antipatterns) > 0 {
		sb.WriteString("## Anti-patterns to Watch For\n")
		for _, a := range antipatterns {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", a.Title, a.Body))
		}
		sb.WriteString("\n")
	}

	if len(patterns) > 0 {
		sb.WriteString("## Recommended Patterns\n")
		for _, p := range patterns {
			sb.WriteString(fmt.Sprintf("- **%s**: %s\n", p.Title, p.Body))
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Code to Review\n\n")
	sb.WriteString(code)
	sb.WriteString("\n\n## Instructions\n")
	sb.WriteString("Respond with a JSON ReviewVerdict:\n")
	sb.WriteString(`{
  "approved": true/false,
  "confidence": 0.0-1.0,
  "issues_found": ["issue1", "issue2"],
  "experience_card_drafts": ["draft title"],
  "suggestions": ["suggestion1"],
  "reasoning": "your reasoning"
}`)
	return sb.String()
}

// parseReviewVerdict extracts a ReviewVerdict from LLM JSON output.
func (k *Keeper) parseReviewVerdict(text string) types.ReviewVerdict {
	v := types.ReviewVerdict{Approved: false, Confidence: 0.5}

	// Simple JSON extraction: find { ... } block
	start := strings.Index(text, "{")
	end := strings.LastIndex(text, "}")
	if start < 0 || end <= start {
		// Fallback: check for approval keywords
		if strings.Contains(strings.ToLower(text), "\"approved\": true") ||
			strings.Contains(strings.ToLower(text), "\"approved\":true") {
			v.Approved = true
		}
		return v
	}

	if err := json.Unmarshal([]byte(text[start:end+1]), &v); err != nil {
		// Fallback
		if strings.Contains(strings.ToLower(text), "approved") &&
			!strings.Contains(strings.ToLower(text), "not approved") {
			v.Approved = true
		}
	}
	return v
}

// extractField pulls a named field from a tagged input string.
func (k *Keeper) extractField(input, field string) string {
	prefix := field + ":"
	for _, line := range strings.Split(input, "\n") {
		if idx := strings.Index(line, prefix); idx >= 0 {
			return strings.TrimSpace(line[idx+len(prefix):])
		}
	}
	return ""
}

// TaskQueue returns the current task queue.
func (k *Keeper) TaskQueue() []types.TaskSpec {
	return k.taskQueue
}

// EnqueueTask adds a task to the keeper's queue.
func (k *Keeper) EnqueueTask(task types.TaskSpec) {
	k.taskQueue = append(k.taskQueue, task)
	k.sink.Emit(event.Event{
		Kind: event.TaskAssigned,
		Federation: &event.FederationPayload{
			Task: &event.FederationTask{
				TaskID:  task.TaskID,
				Title:   task.Title,
				Module:  task.Module,
				AgentID: k.identity.AgentID,
			},
		},
	})
}

// Session returns the agent's session (for use with agent.New).
func (k *Keeper) Session() *agent.Session { return k.session }
