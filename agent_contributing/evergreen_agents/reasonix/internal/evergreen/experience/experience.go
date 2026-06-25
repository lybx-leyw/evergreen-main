// Package experience provides the knowledge store for experience cards — the
// Evergreen federation's shared memory. Supports CRUD, keyword search, type/module/
// tag indexing, and disk persistence (markdown + YAML frontmatter).
//
// Ported from src/experience/store.py + card.py + index.py.
package experience

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"reasonix_gr/internal/evergreen/types"
)

// Store is the knowledge store for experience cards. Thread-safe via sync.RWMutex.
type Store struct {
	mu        sync.RWMutex
	cards     map[string]*types.ExperienceCard
	byType    map[types.ExperienceType][]string
	byModule  map[string][]string
	byTag     map[string][]string
	cardsDir  string
}

// NewStore creates an experience store.
func NewStore(cardsDir string) *Store {
	s := &Store{
		cards:    make(map[string]*types.ExperienceCard),
		byType:   make(map[types.ExperienceType][]string),
		byModule: make(map[string][]string),
		byTag:    make(map[string][]string),
		cardsDir: cardsDir,
	}
	// Pre-populate type buckets
	for _, t := range []types.ExperienceType{types.ExpPattern, types.ExpAntipattern, types.ExpConstraint, types.ExpDeadEnd, types.ExpLesson} {
		s.byType[t] = []string{}
	}
	return s
}

// --- CRUD ---

// Add inserts or updates a card in the store.
func (s *Store) Add(card *types.ExperienceCard) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.addLocked(card)
}

func (s *Store) addLocked(card *types.ExperienceCard) {
	s.cards[card.ID] = card
	s.byType[card.Type] = appendIfMissing(s.byType[card.Type], card.ID)
	if card.Module != "" {
		s.byModule[card.Module] = appendIfMissing(s.byModule[card.Module], card.ID)
	}
	for _, tag := range card.Tags {
		s.byTag[tag] = appendIfMissing(s.byTag[tag], card.ID)
	}
}

// Get returns a card by ID, or nil.
func (s *Store) Get(cardID string) *types.ExperienceCard {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.cards[cardID]
}

// Remove deletes a card. Returns false if not found.
func (s *Store) Remove(cardID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	card := s.cards[cardID]
	if card == nil {
		return false
	}

	delete(s.cards, cardID)
	s.byType[card.Type] = removeFromSlice(s.byType[card.Type], cardID)
	if card.Module != "" {
		s.byModule[card.Module] = removeFromSlice(s.byModule[card.Module], cardID)
	}
	for _, tag := range card.Tags {
		s.byTag[tag] = removeFromSlice(s.byTag[tag], cardID)
	}
	return true
}

// ListAll returns all cards.
func (s *Store) ListAll() []*types.ExperienceCard {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]*types.ExperienceCard, 0, len(s.cards))
	for _, c := range s.cards {
		out = append(out, c)
	}
	return out
}

// Count returns the number of cards.
func (s *Store) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.cards)
}

// --- Search ---

// SearchResult holds a card with its relevance score.
type SearchResult struct {
	Card  *types.ExperienceCard
	Score float64
}

// Search finds cards matching the query. Simple keyword + tag scoring.
func (s *Store) Search(query string, cardType *types.ExperienceType, module string, tags []string, limit int) []SearchResult {
	s.mu.RLock()
	defer s.mu.RUnlock()

	queryLower := strings.ToLower(query)
	var results []SearchResult

	for _, card := range s.cards {
		// Type filter
		if cardType != nil && card.Type != *cardType {
			continue
		}
		// Module filter
		if module != "" && card.Module != module {
			continue
		}
		// Tag filter (any match)
		if len(tags) > 0 {
			hasTag := false
			for _, t := range tags {
				for _, ct := range card.Tags {
					if ct == t {
						hasTag = true
						break
					}
				}
				if hasTag {
					break
				}
			}
			if !hasTag {
				continue
			}
		}

		score := 0.0
		if queryLower != "" && strings.Contains(strings.ToLower(card.Title), queryLower) {
			score += 10.0
		}
		if queryLower != "" && strings.Contains(strings.ToLower(card.Body), queryLower) {
			score += 5.0
		}
		for _, tag := range card.Tags {
			if queryLower != "" && strings.Contains(strings.ToLower(tag), queryLower) {
				score += 3.0
			}
		}

		if queryLower == "" || score > 0 {
			results = append(results, SearchResult{Card: card, Score: score})
		}
	}

	// Sort by score descending
	sort.Slice(results, func(i, j int) bool {
		return results[i].Score > results[j].Score
	})

	if limit > 0 && limit < len(results) {
		results = results[:limit]
	}
	return results
}

// SearchByModule returns cards relevant to a module.
func (s *Store) SearchByModule(module string, limit int) []SearchResult {
	return s.Search("", nil, module, nil, limit)
}

// SearchAntipatterns finds anti-pattern cards whose signatures match code.
func (s *Store) SearchAntipatterns(codeSnippet string) []*types.ExperienceCard {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []*types.ExperienceCard
	for _, id := range s.byType[types.ExpAntipattern] {
		card := s.cards[id]
		if card != nil && card.Signature != "" && strings.Contains(codeSnippet, card.Signature) {
			result = append(result, card)
		}
	}
	return result
}

// SearchConstraints returns constraint cards (hard rules), optionally filtered by module.
func (s *Store) SearchConstraints(module string) []*types.ExperienceCard {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []*types.ExperienceCard
	for _, id := range s.byType[types.ExpConstraint] {
		card := s.cards[id]
		if card != nil && (module == "" || card.Module == module) {
			result = append(result, card)
		}
	}
	return result
}

// --- Disk persistence ---

// LoadFromDisk reads all .md cards from the cards directory and indexes them.
// Returns the number of cards loaded.
func (s *Store) LoadFromDisk() int {
	if s.cardsDir == "" {
		return 0
	}

	entries, err := os.ReadDir(s.cardsDir)
	if err != nil {
		return 0
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	loaded := 0
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") {
			continue
		}
		mdPath := filepath.Join(s.cardsDir, entry.Name())
		data, err := os.ReadFile(mdPath)
		if err != nil {
			continue
		}

		relPath := entry.Name()
		card := types.FromMarkdown(string(data), relPath)
		if card.ID == "" {
			continue
		}
		s.addLocked(&card)
		loaded++
	}
	return loaded
}

// Stats returns summary statistics.
func (s *Store) Stats() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	byType := make(map[string]int)
	for t, ids := range s.byType {
		if len(ids) > 0 {
			byType[string(t)] = len(ids)
		}
	}
	byModule := make(map[string]int)
	for m, ids := range s.byModule {
		byModule[m] = len(ids)
	}

	return map[string]interface{}{
		"total":      len(s.cards),
		"by_type":    byType,
		"by_module":  byModule,
		"tag_count":  len(s.byTag),
	}
}

// ---------------------------------------------------------------------------
// EXPERIENCE.md index management (port of index.py)
// ---------------------------------------------------------------------------

// BuildIndex generates the EXPERIENCE.md master index content.
func (s *Store) BuildIndex() string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var b strings.Builder
	b.WriteString("# Experience Library Index\n\n")
	b.WriteString("> Auto-generated by Evergreen Librarian.\n\n")

	// Group cards by type
	categories := map[types.ExperienceType]string{
		types.ExpPattern:     "## Patterns (reusable approaches)",
		types.ExpAntipattern: "## Anti-patterns (things to avoid)",
		types.ExpConstraint:  "## Constraints (hard rules)",
		types.ExpDeadEnd:     "## Dead Ends (approaches proven impossible)",
		types.ExpLesson:      "## Lessons (general learnings)",
	}

	order := []types.ExperienceType{types.ExpPattern, types.ExpAntipattern, types.ExpConstraint, types.ExpDeadEnd, types.ExpLesson}
	for _, t := range order {
		ids := s.byType[t]
		if len(ids) == 0 {
			continue
		}
		b.WriteString("\n")
		b.WriteString(categories[t])
		b.WriteString("\n\n")

		for _, id := range ids {
			card := s.cards[id]
			if card == nil || card.Status != types.CardApproved {
				continue
			}
			tagStr := strings.Join(card.Tags, ", ")
			b.WriteString("- **")
			b.WriteString(card.Title)
			b.WriteString("**")
			if card.Module != "" {
				b.WriteString(" (`" + card.Module + "`)")
			}
			b.WriteString("\n")
			if tagStr != "" {
				b.WriteString("  Tags: " + tagStr + "\n")
			}
		}
	}

	return b.String()
}

// InjectForTask returns patterns, antipatterns, and constraints relevant to a task.
// This is the RAG injection used before agent code generation.
func (s *Store) InjectForTask(module, title string) (patterns, antipatterns, constraints []*types.ExperienceCard) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	queryLower := strings.ToLower(title)

	for _, card := range s.cards {
		if card.Status != types.CardApproved {
			continue
		}

		// Relevance: module match or keyword match
		relevant := card.Module == module
		if !relevant && queryLower != "" {
			relevant = strings.Contains(strings.ToLower(card.Title), queryLower) ||
				strings.Contains(strings.ToLower(card.Body), queryLower)
		}
		if !relevant {
			continue
		}

		switch card.Type {
		case types.ExpPattern:
			patterns = append(patterns, card)
		case types.ExpAntipattern:
			antipatterns = append(antipatterns, card)
		case types.ExpConstraint:
			constraints = append(constraints, card)
		}
	}
	return
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func appendIfMissing(slice []string, s string) []string {
	for _, v := range slice {
		if v == s {
			return slice
		}
	}
	return append(slice, s)
}

func removeFromSlice(slice []string, s string) []string {
	for i, v := range slice {
		if v == s {
			return append(slice[:i], slice[i+1:]...)
		}
	}
	return slice
}
