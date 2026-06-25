package federation

import (
	"fmt"
	"strings"

	"reasonix_gr/internal/event"
)

// MonitorSink implements event.Sink and writes formatted agent events
// (reasoning, tool calls, text, errors) to an OutputBuffer so the user
// can watch any agent's full thought process in real-time.
type MonitorSink struct {
	monitor   *Monitor
	agentID   string
	maxLines  int
	textBuf   strings.Builder // accumulates streaming text deltas
	reasonBuf strings.Builder // accumulates streaming reasoning deltas
}

// NewMonitorSink creates a sink that streams agent events to the monitor.
func NewMonitorSink(monitor *Monitor, agentID string) *MonitorSink {
	return &MonitorSink{monitor: monitor, agentID: agentID, maxLines: 500}
}

// Emit implements event.Sink. Each event kind is formatted into a
// human-readable line and appended to the agent's output buffer.
func (s *MonitorSink) Emit(e event.Event) {
	switch e.Kind {
	case event.TurnStarted:
		s.append("─── Turn started ───")

	case event.Reasoning:
		s.reasonBuf.WriteString(e.Text)
		s.flushAccumulated("💭", &s.reasonBuf)

	case event.Text:
		s.textBuf.WriteString(e.Text)
		s.flushAccumulated("💬", &s.textBuf)

	case event.Message:
		// Flush any remaining buffered text
		s.flushAll("💭", &s.reasonBuf)
		s.flushAll("💬", &s.textBuf)
		if e.Text != "" {
			s.append(fmt.Sprintf("💬 %s", e.Text))
		}

	case event.ToolDispatch:
		toolName := ""
		if e.Tool.Name != "" {
			toolName = e.Tool.Name
		}
		args := truncateStr(e.Tool.Args, 80)
		ro := ""
		if e.Tool.ReadOnly {
			ro = " [ro]"
		}
		s.append(fmt.Sprintf("🔧 %s(%s)%s", toolName, args, ro))

	case event.ToolResult:
		output := e.Tool.Output
		if e.Tool.Err != "" {
			output = "ERROR: " + e.Tool.Err
		}
		duration := ""
		if e.Tool.DurationMs > 0 {
			duration = fmt.Sprintf(" (%dms)", e.Tool.DurationMs)
		}
		output = truncateStr(output, 200)
		for _, line := range splitLines(output, 100) {
			s.append(fmt.Sprintf("  → %s%s", line, duration))
		}

	case event.ToolProgress:
		for _, line := range splitLines(e.Text, 100) {
			s.append(fmt.Sprintf("  … %s", line))
		}

	case event.Usage:
		if e.Usage != nil {
			s.append(fmt.Sprintf("📊 tokens: %d↓ %d↑ (cache: %d hit)", e.Usage.PromptTokens, e.Usage.CompletionTokens, e.Usage.CacheHitTokens))
		}

	case event.Notice:
		level := ""
		if e.Level == event.LevelWarn {
			level = "⚠️ "
		}
		s.append(fmt.Sprintf("%s%s", level, e.Text))

	case event.Phase:
		s.append(fmt.Sprintf("◆ %s", e.Text))

	case event.TurnDone:
		s.flushAll("💭", &s.reasonBuf)
		s.flushAll("💬", &s.textBuf)
		if e.Err != nil {
			s.append(fmt.Sprintf("❌ Error: %v", e.Err))
		} else {
			s.append("─── Turn complete ───")
		}

	case event.CompactionStarted:
		s.append("⏳ Compacting context...")

	case event.CompactionDone:
		s.append("✅ Compaction complete")

	case event.Retrying:
		s.append(fmt.Sprintf("🔄 Retrying (%d/%d)...", e.RetryAttempt, e.RetryMax))

	// Federation events
	case event.FederationStarted:
		s.append("🚀 Federation started")
	case event.FederationCompleted:
		s.append("✅ Federation complete")
	case event.FederationAborted:
		s.append("❌ Federation aborted")
	case event.TaskCreated:
		if e.Federation != nil && e.Federation.Task != nil {
			s.append(fmt.Sprintf("📋 Task: %s [%s]", e.Federation.Task.Title, e.Federation.Task.Module))
		}
	case event.ContractProposed, event.ContractAccepted, event.ContractRejected:
		if e.Federation != nil && e.Federation.Contract != nil {
			s.append(fmt.Sprintf("📜 Contract %s: %s", shortKind(e.Kind), e.Federation.Contract.Title))
		}
	case event.ExperienceApproved:
		if e.Federation != nil && e.Federation.Experience != nil {
			s.append(fmt.Sprintf("📚 XP approved: %s", e.Federation.Experience.Title))
		}
	case event.CreditChanged:
		if e.Federation != nil && e.Federation.Credit != nil {
			s.append(fmt.Sprintf("⭐ Credit: %s %+.1f → %.1f",
				e.Federation.Credit.Dimension, e.Federation.Credit.Delta, e.Federation.Credit.NewScore))
		}
	}
}

func (s *MonitorSink) append(line string) {
	s.monitor.Append(s.agentID, line)
}

// flushAccumulated writes complete lines from the buffer, leaving incomplete
// lines for the next delta. This keeps streaming text readable.
func (s *MonitorSink) flushAccumulated(prefix string, buf *strings.Builder) {
	text := buf.String()
	for {
		idx := strings.IndexByte(text, '\n')
		if idx < 0 {
			break
		}
		line := strings.TrimRight(text[:idx], "\r")
		if line != "" {
			s.append(fmt.Sprintf("%s %s", prefix, line))
		}
		text = text[idx+1:]
	}
	buf.Reset()
	if text != "" {
		buf.WriteString(text)
	}
}

// flushAll writes all remaining buffered text, even incomplete lines.
func (s *MonitorSink) flushAll(prefix string, buf *strings.Builder) {
	if buf.Len() > 0 {
		text := strings.TrimSpace(buf.String())
		if text != "" {
			s.append(fmt.Sprintf("%s %s", prefix, text))
		}
		buf.Reset()
	}
}

// splitLines breaks text into lines at maxLen, trying to break at word boundaries.
func splitLines(text string, maxLen int) []string {
	if len(text) <= maxLen {
		if text == "" {
			return nil
		}
		return []string{text}
	}
	var lines []string
	remaining := text
	for len(remaining) > maxLen {
		cut := maxLen
		// Try to break at space
		if idx := strings.LastIndexByte(remaining[:maxLen], ' '); idx > maxLen/2 {
			cut = idx
		}
		lines = append(lines, strings.TrimSpace(remaining[:cut]))
		remaining = strings.TrimSpace(remaining[cut:])
	}
	if remaining != "" {
		lines = append(lines, remaining)
	}
	return lines
}

func shortKind(k event.Kind) string {
	switch k {
	case event.ContractProposed:
		return "proposed"
	case event.ContractAccepted:
		return "accepted"
	case event.ContractRejected:
		return "rejected"
	default:
		return fmt.Sprintf("kind-%d", k)
	}
}

// TeeSink wraps a parent sink and also forwards events to it.
// Useful for: show agent output in terminal AND capture to monitor.
func TeeSink(primary, secondary event.Sink) event.Sink {
	return event.FuncSink(func(e event.Event) {
		primary.Emit(e)
		if secondary != nil {
			secondary.Emit(e)
		}
	})
}
