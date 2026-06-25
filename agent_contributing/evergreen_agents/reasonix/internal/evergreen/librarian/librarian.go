// Package librarian implements the Librarian agent — the experience card curator.
// It reviews proposed cards for quality and novelty, detects duplicates via
// semantic similarity, handles superseeding (version chains), and rebuilds the
// EXPERIENCE.md master index. Uses the deep-thinking LLM tier.
//
// Ported from src/agents/librarian.py.
package librarian

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"reasonix_gr/internal/agent"
	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/experience"
	"reasonix_gr/internal/evergreen/types"
	"reasonix_gr/internal/provider"
	"reasonix_gr/internal/tool"
)

// Librarian is the experience card curator agent. It implements agent.Runner.
type Librarian struct {
	identity types.AgentIdentity
	prov     provider.Provider
	registry *tool.Registry
	session  *agent.Session
	sink     event.Sink
	store    *experience.Store
}

// New creates a Librarian agent.
func New(
	identity types.AgentIdentity,
	prov provider.Provider,
	registry *tool.Registry,
	session *agent.Session,
	sink event.Sink,
	store *experience.Store,
) *Librarian {
	return &Librarian{
		identity: identity,
		prov:     prov,
		registry: registry,
		session:  session,
		sink:     sink,
		store:    store,
	}
}

// Identity returns the librarian's agent identity.
func (l *Librarian) Identity() types.AgentIdentity { return l.identity }

// Run implements agent.Runner. Processes experience card review requests.
func (l *Librarian) Run(ctx context.Context, input string) error {
	l.sink.Emit(event.Event{
		Kind: event.Phase,
		Text: "librarian · experience curation",
		Federation: &event.FederationPayload{
			System: &event.FederationSystem{AgentID: l.identity.AgentID},
		},
	})

	switch {
	case strings.Contains(input, "review:"):
		return l.handleReview(ctx, input)
	case strings.Contains(input, "rebuild_index"):
		return l.handleRebuildIndex(ctx)
	case strings.Contains(input, "stats"):
		return l.handleStats(ctx)
	default:
		return l.handleReview(ctx, input)
	}
}

// handleReview reviews a proposed experience card for quality, novelty, and duplication.
func (l *Librarian) handleReview(ctx context.Context, input string) error {
	cardTitle := l.extractField(input, "card")
	if cardTitle == "" {
		cardTitle = input
	}

	// Search for duplicates
	results := l.store.Search(cardTitle, nil, "", nil, 5)

	// Build curation prompt
	prompt := l.buildCurationPrompt(cardTitle, results)

	l.session.Add(provider.Message{Role: "user", Content: prompt})

	req := provider.Request{
		Messages:    l.session.Messages,
		Tools:       l.registry.Schemas(),
		Temperature: 0.3,
		MaxTokens:   4096,
	}

	stream, err := l.prov.Stream(ctx, req)
	if err != nil {
		return err
	}

	var fullText strings.Builder
	for chunk := range stream {
		if chunk.Text != "" {
			fullText.WriteString(chunk.Text)
			l.sink.Emit(event.Event{Kind: event.Text, Text: chunk.Text})
		}
	}

	// Parse the librarian's decision
	draft := l.parseCardDraft(fullText.String())

	if draft.Title != "" {
		card := types.ExperienceCard{
			Type:       draft.Type,
			Title:      draft.Title,
			Tags:       draft.Tags,
			Module:     draft.Module,
			Severity:   draft.Severity,
			Signature:  draft.Signature,
			Body:       draft.Body,
			Supersedes: draft.Supersedes,
			Status:     types.CardApproved,
		}

		l.store.Add(&card)

		// Handle superseeding
		if draft.Supersedes != "" {
			if existing := l.store.Get(draft.Supersedes); existing != nil {
				existing.Status = types.CardSuperseded
				existing.SupersededBy = card.ID
				l.sink.Emit(event.Event{
					Kind: event.ExperienceSuperseded,
					Federation: &event.FederationPayload{
						Experience: &event.FederationExperience{
							CardID:       existing.ID,
							Title:        existing.Title,
							Type:         string(existing.Type),
							SupersededBy: card.ID,
						},
					},
				})
			}
		}

		l.sink.Emit(event.Event{
			Kind: event.ExperienceApproved,
			Federation: &event.FederationPayload{
				Experience: &event.FederationExperience{
					CardID: card.ID,
					Title:  card.Title,
					Type:   string(card.Type),
				},
			},
		})
	}

	l.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// handleRebuildIndex rebuilds the EXPERIENCE.md master index.
func (l *Librarian) handleRebuildIndex(ctx context.Context) error {
	index := l.store.BuildIndex()

	l.sink.Emit(event.Event{
		Kind: event.Text,
		Text: fmt.Sprintf("EXPERIENCE.md rebuilt:\n\n%s", index),
	})

	l.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// handleStats returns experience library statistics.
func (l *Librarian) handleStats(ctx context.Context) error {
	stats := l.store.Stats()
	statsJSON, _ := json.MarshalIndent(stats, "", "  ")

	l.sink.Emit(event.Event{
		Kind: event.Text,
		Text: fmt.Sprintf("Experience Library Stats:\n```json\n%s\n```", string(statsJSON)),
	})

	l.sink.Emit(event.Event{Kind: event.TurnDone})
	return nil
}

// buildCurationPrompt constructs the LLM prompt for card curation.
func (l *Librarian) buildCurationPrompt(title string, existing []experience.SearchResult) string {
	var sb strings.Builder
	sb.WriteString("You are the Librarian agent — curator of the Evergreen experience library.\n\n")
	sb.WriteString("## Your Role\n")
	sb.WriteString("- Review proposed experience cards for quality, clarity, and novelty.\n")
	sb.WriteString("- Detect duplicates and decide whether to approve, reject, or supersede.\n")
	sb.WriteString("- Curate cards to keep the library high-signal.\n\n")

	sb.WriteString("## Proposed Card\n")
	sb.WriteString(fmt.Sprintf("Title: %s\n\n", title))

	if len(existing) > 0 {
		sb.WriteString("## Existing Similar Cards\n")
		for _, r := range existing {
			sb.WriteString(fmt.Sprintf("- **%s** (type: %s, score: %.0f)\n  %s\n",
				r.Card.Title, r.Card.Type, r.Score, truncate(r.Card.Body, 200)))
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Instructions\n")
	sb.WriteString("Respond with a JSON ExperienceCardDraft:\n")
	sb.WriteString(`{
  "type": "pattern|antipattern|constraint|dead_end|lesson",
  "title": "card title",
  "tags": ["tag1", "tag2"],
  "module": "module_name",
  "severity": "info|warning|blocking",
  "signature": "code fingerprint (for antipatterns)",
  "body": "detailed markdown body",
  "supersedes": "card_id_or_null"
}`)
	return sb.String()
}

// parseCardDraft extracts an ExperienceCardDraft from LLM JSON output.
func (l *Librarian) parseCardDraft(text string) types.ExperienceCardDraft {
	var draft types.ExperienceCardDraft

	start := strings.Index(text, "{")
	end := strings.LastIndex(text, "}")
	if start < 0 || end <= start {
		return draft
	}

	if err := json.Unmarshal([]byte(text[start:end+1]), &draft); err != nil {
		draft.Title = l.extractField(text, "title")
		draft.Body = text
	}
	return draft
}

func (l *Librarian) extractField(input, field string) string {
	prefix := field + ":"
	for _, line := range strings.Split(input, "\n") {
		if idx := strings.Index(line, prefix); idx >= 0 {
			return strings.TrimSpace(line[idx+len(prefix):])
		}
	}
	return ""
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

// Session returns the agent's session.
func (l *Librarian) Session() *agent.Session { return l.session }
