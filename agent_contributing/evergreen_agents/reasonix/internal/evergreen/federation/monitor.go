package federation

import (
	"fmt"
	"strings"
	"sync"
	"time"
)

// Monitor tracks the live output of every agent in the fleet. The user can
// query which agents are working and watch any agent's output in real-time.
//
//	/agents              — list all agents with status
//	/watch keeper-auth   — see live output from the auth keeper
//	/unwatch             — return to CEO view

// AgentStatus is the current state of one agent.
type AgentStatus struct {
	ID        string
	Role      string
	Module    string
	State     AgentState_    // idle | working | done | error
	StartedAt time.Time
	Output    *OutputBuffer // ring buffer of recent output lines
}

// AgentState_ is the working state of an agent.
type AgentState_ string

const (
	AgentIdle_    AgentState_ = "idle"
	AgentWorking  AgentState_ = "working"
	AgentDone     AgentState_ = "done"
	AgentError_   AgentState_ = "error"
)

// OutputBuffer is a fixed-size ring buffer of output lines.
type OutputBuffer struct {
	mu    sync.Mutex
	lines []string
	pos   int
	full  bool
	max   int
}

// NewOutputBuffer creates a ring buffer for agent output.
func NewOutputBuffer(maxLines int) *OutputBuffer {
	if maxLines <= 0 {
		maxLines = 200
	}
	return &OutputBuffer{
		lines: make([]string, maxLines),
		max:   maxLines,
	}
}

// Append adds a line to the buffer.
func (b *OutputBuffer) Append(line string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.lines[b.pos%b.max] = line
	b.pos++
	if b.pos >= b.max {
		b.full = true
	}
}

// Snapshot returns all buffered lines in order.
func (b *OutputBuffer) Snapshot() []string {
	b.mu.Lock()
	defer b.mu.Unlock()

	if !b.full {
		out := make([]string, b.pos)
		copy(out, b.lines[:b.pos])
		return out
	}

	out := make([]string, b.max)
	start := b.pos % b.max
	copy(out, b.lines[start:])
	copy(out[b.max-start:], b.lines[:start])
	return out
}

// Tail returns the last n lines.
func (b *OutputBuffer) Tail(n int) []string {
	lines := b.Snapshot()
	if len(lines) <= n {
		return lines
	}
	return lines[len(lines)-n:]
}

// Monitor tracks the fleet's agents.
type Monitor struct {
	mu      sync.RWMutex
	agents  map[string]*AgentStatus // agentID → status
	history []string                 // recent events log
}

// NewMonitor creates an agent monitor.
func NewMonitor() *Monitor {
	return &Monitor{
		agents: make(map[string]*AgentStatus),
	}
}

// Register adds an agent to the monitor.
func (m *Monitor) Register(id, role, module string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.agents[id] = &AgentStatus{
		ID:     id,
		Role:   role,
		Module: module,
		State:  AgentIdle_,
		Output: NewOutputBuffer(200),
	}
	m.history = append(m.history, fmt.Sprintf("[%s] %s (%s) registered", time.Now().Format("15:04:05"), id, role))
}

// SetState updates an agent's working state.
func (m *Monitor) SetState(id string, state AgentState_) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if a, ok := m.agents[id]; ok {
		a.State = state
		if state == AgentWorking {
			a.StartedAt = time.Now()
		}
		emoji := map[AgentState_]string{AgentIdle_: "💤", AgentWorking: "⚡", AgentDone: "✅", AgentError_: "❌"}
		m.history = append(m.history, fmt.Sprintf("[%s] %s %s %s", time.Now().Format("15:04:05"), emoji[state], id, state))
	}
}

// Append appends output to an agent's buffer.
func (m *Monitor) Append(id, line string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if a, ok := m.agents[id]; ok {
		a.Output.Append(line)
	}
}

// Get returns an agent's status.
func (m *Monitor) Get(id string) *AgentStatus {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.agents[id]
}

// ListActive returns agents that are currently working.
func (m *Monitor) ListActive() []*AgentStatus {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var active []*AgentStatus
	for _, a := range m.agents {
		if a.State == AgentWorking {
			active = append(active, a)
		}
	}
	return active
}

// ListAll returns all agents with their status.
func (m *Monitor) ListAll() []*AgentStatus {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var all []*AgentStatus
	for _, a := range m.agents {
		all = append(all, a)
	}
	return all
}

// SortedList returns agents sorted by status (working first) then module name.
func (m *Monitor) SortedList() []*AgentStatus {
	all := m.ListAll()
	stateOrder := map[AgentState_]int{AgentWorking: 0, AgentDone: 1, AgentError_: 2, AgentIdle_: 3}
	for i := 0; i < len(all); i++ {
		for j := i + 1; j < len(all); j++ {
			oi, oj := stateOrder[all[i].State], stateOrder[all[j].State]
			if oi > oj || (oi == oj && all[i].Module > all[j].Module) {
				all[i], all[j] = all[j], all[i]
			}
		}
	}
	return all
}

// FindAgent looks up an agent by numeric dashboard index (1-based) or by name/ID substring.
func (m *Monitor) FindAgent(target string) *AgentStatus {
	all := m.SortedList()
	// Try numeric index
	if n, err := fmt.Sscanf(target, "%d", new(int)); err == nil && n == 1 {
		// Sscanf doesn't work this way; use simple check
	}
	idx := 0
	if _, err := fmt.Sscanf(target, "%d", &idx); err == nil && idx > 0 && idx <= len(all) {
		return all[idx-1]
	}
	// Try name/ID match
	for _, a := range all {
		if a.ID == target || strings.Contains(a.ID, target) {
			return a
		}
	}
	return nil
}

// StatusBar returns a one-line summary of the fleet.
func (m *Monitor) StatusBar() string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	total := len(m.agents)
	working := 0
	for _, a := range m.agents {
		if a.State == AgentWorking {
			working++
		}
	}

	if working == 0 {
		return fmt.Sprintf("Fleet: %d agents · all idle", total)
	}

	var workingNames []string
	for _, a := range m.agents {
		if a.State == AgentWorking {
			workingNames = append(workingNames, fmt.Sprintf("%s(%s)", a.ID, a.Module))
		}
	}
	return fmt.Sprintf("Fleet: %d agents · %d working: %s", total, working, strings.Join(workingNames, ", "))
}

// RenderDashboard returns a formatted dashboard of ALL agents, sorted by status then module.
func (m *Monitor) RenderDashboard() string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var b strings.Builder
	b.WriteString("┌──────────────────────────────────────────────────────────┐\n")
	b.WriteString("│                  Agent Dashboard (all)                    │\n")
	b.WriteString("├─────┬──────────────────────────┬────────────┬────────────┤\n")
	b.WriteString("│  #  │ Agent                    │ Module     │ Status     │\n")
	b.WriteString("├─────┼──────────────────────────┼────────────┼────────────┤\n")

	icons := map[AgentState_]string{
		AgentIdle_: "💤 idle", AgentWorking: "⚡ working",
		AgentDone: "✅ done", AgentError_: "❌ error",
	}

	// Sort: working first, then by module name
	type entry struct {
		id     string
		module string
		state  AgentState_
		ago    string
	}
	var entries []entry
	for _, a := range m.agents {
		ago := ""
		if !a.StartedAt.IsZero() && a.State != AgentIdle_ {
			ago = " " + time.Since(a.StartedAt).Round(time.Second).String()
		}
		entries = append(entries, entry{a.ID, a.Module, a.State, ago})
	}
	// Sort: working > done > error > idle, then by module name
	stateOrder := map[AgentState_]int{AgentWorking: 0, AgentDone: 1, AgentError_: 2, AgentIdle_: 3}
	for i := 0; i < len(entries); i++ {
		for j := i + 1; j < len(entries); j++ {
			oi, oj := stateOrder[entries[i].state], stateOrder[entries[j].state]
			if oi > oj || (oi == oj && entries[i].module > entries[j].module) {
				entries[i], entries[j] = entries[j], entries[i]
			}
		}
	}

	for i, e := range entries {
		b.WriteString(fmt.Sprintf("│ %3d │ %-24s │ %-10s │ %s%-10s│\n",
			i+1, e.id, e.module, icons[e.state], e.ago))
	}

	if len(entries) == 0 {
		b.WriteString("│      (no agents registered)                              │\n")
	}

	b.WriteString("└─────┴──────────────────────────┴────────────┴────────────┘\n")
	b.WriteString(fmt.Sprintf("%d agents. /watch <N> or /watch <agent-id>\n", len(entries)))
	return b.String()
}

// RenderAgentOutput returns the output buffer for a specific agent.
func (m *Monitor) RenderAgentOutput(id string, tail int) string {
	if tail <= 0 {
		tail = 50
	}

	a := m.Get(id)
	if a == nil {
		return fmt.Sprintf("Agent '%s' not found. Type /agents to list all.\n", id)
	}

	lines := a.Output.Tail(tail)

	var b strings.Builder
	b.WriteString(fmt.Sprintf("┌─ %s (%s/%s) — %s ──────────────┐\n",
		a.ID, a.Role, a.Module, a.State))
	b.WriteString("│ Watching live output. /unwatch to return to CEO.\n")
	b.WriteString("├───────────────────────────────────────────────┤\n")

	if len(lines) == 0 {
		b.WriteString("│ (no output yet)                                │\n")
	} else {
		for _, line := range lines {
			// Truncate long lines
			if len(line) > 60 {
				line = line[:57] + "..."
			}
			b.WriteString("│ " + line + "\n")
		}
	}
	b.WriteString("└───────────────────────────────────────────────┘\n")
	return b.String()
}
