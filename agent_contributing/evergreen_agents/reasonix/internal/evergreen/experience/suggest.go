package experience

import (
	"fmt"
	"regexp"
	"strings"
)

// Suggestion matches a CI/test error against the experience library and
// returns relevant cards that might help the developer.
type Suggestion struct {
	Error    string // the original error message
	Card     string // card title
	CardID   string // card ID
	Match    string // what matched (signature, keyword, etc.)
	MatchType string // "signature" | "keyword" | "pattern"
	Score    int
}

// Suggest analyses a build/test failure against the experience store.
// Returns up to `limit` matching suggestions, ranked by relevance.
//
// This powers the "CI failure → experience link" automation.
func (s *Store) Suggest(errorOutput string, limit int) []Suggestion {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if limit <= 0 {
		limit = 5
	}

	var results []Suggestion
	errorLower := strings.ToLower(errorOutput)

	for _, card := range s.cards {
		if card.Status != "approved" {
			continue
		}

		sug := Suggestion{Error: errorOutput, Card: card.Title, CardID: card.ID}

		// 1. Signature match (exact code fingerprint — highest confidence)
		if card.Signature != "" && strings.Contains(errorLower, strings.ToLower(card.Signature)) {
			sug.Match = card.Signature
			sug.MatchType = "signature"
			sug.Score = 100
			results = append(results, sug)
			continue
		}

		// 2. Anti-pattern pattern match (regex from card body)
		if card.Type == "antipattern" {
			patterns := extractPatterns(card.Body)
			for _, p := range patterns {
				if matched, _ := regexp.MatchString("(?i)"+p, errorOutput); matched {
					sug.Match = p
					sug.MatchType = "pattern"
					sug.Score = 80
					results = append(results, sug)
					break
				}
			}
			if sug.Score > 0 {
				continue
			}
		}

		// 3. Keyword match (title or body keywords in error)
		keywords := extractKeywords(card.Title, card.Body)
		hits := 0
		for _, kw := range keywords {
			if strings.Contains(errorLower, kw) {
				hits++
			}
		}
		if hits >= 2 || (hits >= 1 && card.Type == "constraint") {
			sug.Match = strings.Join(keywords, ", ")
			sug.MatchType = "keyword"
			sug.Score = 40 + hits*10
			results = append(results, sug)
		}
	}

	// Sort by score descending
	for i := 0; i < len(results); i++ {
		for j := i + 1; j < len(results); j++ {
			if results[j].Score > results[i].Score {
				results[i], results[j] = results[j], results[i]
			}
		}
	}

	if len(results) > limit {
		results = results[:limit]
	}
	return results
}

// FormatSuggestions renders suggestions as a human-readable message,
// suitable for CI bot comments or terminal output.
func FormatSuggestions(suggestions []Suggestion) string {
	if len(suggestions) == 0 {
		return ""
	}

	var b strings.Builder
	b.WriteString("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	b.WriteString("📚 Experience Library suggests:\n")
	b.WriteString("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

	for i, s := range suggestions {
		icon := map[string]string{"signature": "🎯", "pattern": "🔍", "keyword": "💡"}[s.MatchType]
		b.WriteString(fmt.Sprintf("%d. %s **%s** (score: %d)\n", i+1, icon, s.Card, s.Score))
		b.WriteString(fmt.Sprintf("   Match: %s (%s)\n", s.Match, s.MatchType))
		if s.CardID != "" {
			b.WriteString(fmt.Sprintf("   Card: %s\n", s.CardID))
		}
		b.WriteString("\n")
	}

	b.WriteString("Review these cards for guidance on fixing this issue.\n")
	return b.String()
}

// BuildFailureAnalyzer analyses CI failures and suggests experience cards.
type BuildFailureAnalyzer struct {
	store *Store
}

// NewBuildFailureAnalyzer creates an analyzer backed by the experience store.
func NewBuildFailureAnalyzer(store *Store) *BuildFailureAnalyzer {
	return &BuildFailureAnalyzer{store: store}
}

// Analyze analyses a CI build failure and returns formatted suggestions.
func (a *BuildFailureAnalyzer) Analyze(buildOutput string) string {
	suggestions := a.store.Suggest(buildOutput, 5)
	return FormatSuggestions(suggestions)
}

// extractPatterns looks for code patterns in card body (backtick-wrapped snippets).
func extractPatterns(body string) []string {
	re := regexp.MustCompile("`([^`]+)`")
	matches := re.FindAllStringSubmatch(body, -1)
	var patterns []string
	for _, m := range matches {
		if len(m) > 1 && len(m[1]) > 3 && !strings.Contains(m[1], " ") {
			patterns = append(patterns, regexp.QuoteMeta(m[1]))
		}
	}
	return patterns
}

// extractKeywords returns meaningful keywords from title and body.
func extractKeywords(title, body string) []string {
	text := strings.ToLower(title + " " + body)
	// Remove common words
	stop := map[string]bool{"the": true, "a": true, "an": true, "is": true, "are": true,
		"was": true, "were": true, "be": true, "been": true, "in": true, "on": true,
		"at": true, "to": true, "for": true, "of": true, "with": true, "and": true,
		"or": true, "not": true, "this": true, "that": true, "it": true, "its": true}

	words := strings.Fields(text)
	var result []string
	seen := map[string]bool{}
	for _, w := range words {
		w = strings.Trim(w, ".,;:!?()[]{}'\"")
		if len(w) > 3 && !stop[w] && !seen[w] {
			seen[w] = true
			result = append(result, w)
		}
	}
	return result
}
