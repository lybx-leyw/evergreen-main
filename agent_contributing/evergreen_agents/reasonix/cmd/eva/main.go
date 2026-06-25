// Command eva is the Evergreen Agent Federation CLI — a multi-agent wrapper
// built on top of Reasonix. It imports Reasonix as a library and adds
// multi-agent orchestration: Planner → Keeper → Executor → Review.
package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"reasonix_gr/internal/boot"
	"reasonix_gr/internal/event"

	// Blank imports wire compile-time built-ins.
	_ "reasonix_gr/internal/provider/anthropic"
	_ "reasonix_gr/internal/provider/openai"
	_ "reasonix_gr/internal/tool/builtin"
)

var version = "evergreen-dev"

func main() {
	if len(os.Args) < 2 {
		fmt.Println("eva — Evergreen Agent Federation CLI")
		fmt.Println()
		fmt.Println("Usage:")
		fmt.Println("  eva orchestrate <task>    Run multi-agent pipeline (Planner → Keeper × N → Executor × N)")
		fmt.Println("  eva run <task>            Run single-agent (passthrough to Reasonix)")
		fmt.Println("  eva version               Show version")
		os.Exit(0)
	}

	cmd := os.Args[1]
	switch cmd {
	case "orchestrate":
		task := strings.Join(os.Args[2:], " ")
		if task == "" {
			fmt.Fprintln(os.Stderr, "Usage: eva orchestrate <task>")
			os.Exit(1)
		}
		os.Exit(orchestrate(task))

	case "run":
		// Passthrough: single agent (same as reasonix run)
		task := strings.Join(os.Args[2:], " ")
		os.Exit(runSingle(task))

	case "version":
		fmt.Println("eva", version, "(Reasonix multi-agent wrapper)")
		os.Exit(0)

	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", cmd)
		os.Exit(1)
	}
}

// ==========================================================================
// Single-agent run (passthrough to Reasonix)
// ==========================================================================

func runSingle(task string) int {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	sink := &textSink{}
	ctrl, err := boot.Build(ctx, boot.Options{
		Sink: sink,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Boot error: %v\n", err)
		return 1
	}
	defer ctrl.Close()

	if err := ctrl.Run(ctx, task); err != nil {
		fmt.Fprintf(os.Stderr, "Run error: %v\n", err)
		return 1
	}
	return 0
}

// ==========================================================================
// Multi-agent orchestration
// ==========================================================================

func orchestrate(task string) int {
	fmt.Printf("🌲 Evergreen Multi-Agent Orchestrator\n")
	fmt.Printf("📋 Task: %s\n\n", task)

	modules := detectModules(task)
	if len(modules) == 0 {
		modules = []string{"core"}
	}

	fmt.Printf("📦 Modules involved: %s\n", strings.Join(modules, ", "))
	fmt.Printf("👤 Keepers: %d\n", len(modules))
	fmt.Printf("🔧 Executors: %d\n\n", len(modules))

	// Phase 1: Planner
	fmt.Println("══ Phase 1: Planning ══")
	plan := runPlanner(task, modules)
	fmt.Printf("  Plan: %s\n\n", plan)

	// Phase 2: Execute per module (parallel via goroutines)
	fmt.Println("══ Phase 2: Execution (parallel) ══")
	var wg sync.WaitGroup
	results := make(chan string, len(modules))

	for _, mod := range modules {
		wg.Add(1)
		go func(module string) {
			defer wg.Done()
			result := runExecutor(module, task)
			results <- fmt.Sprintf("[%s] %s", module, result)
		}(mod)
	}

	wg.Wait()
	close(results)

	// Collect results
	fmt.Println()
	fmt.Println("══ Results ══")
	for r := range results {
		fmt.Printf("  ✅ %s\n", r)
	}

	fmt.Println("\n✓ Multi-agent pipeline complete")
	return 0
}

// ==========================================================================
// Module detection (simple keyword matching)
// ==========================================================================

func detectModules(task string) []string {
	allModules := []string{
		"auth", "agent", "courses", "todo", "plan", "scores", "exams",
		"downloads", "tutor", "translate", "classroom", "wordpecker", "quiz",
		"zdbk", "pintia", "teachers", "schedule", "library", "ecard",
		"autosign", "rvpn", "palace", "connectivity", "scheduler", "settings",
	}
	var found []string
	taskLower := strings.ToLower(task)
	for _, m := range allModules {
		if strings.Contains(taskLower, m) {
			found = append(found, m)
		}
	}
	return found
}

// ==========================================================================
// Agent runners
// ==========================================================================

func runPlanner(task string, modules []string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	var output strings.Builder
	sink := &collectSink{buf: &output}

	ctrl, err := boot.Build(ctx, boot.Options{Sink: sink})
	if err != nil {
		return fmt.Sprintf("boot error: %v", err)
	}
	defer ctrl.Close()

	prompt := fmt.Sprintf(
		"You are the Planner Agent. Decompose this task into subtasks, one per module. "+
			"Modules involved: %s. Task: %s. Return a numbered list.",
		strings.Join(modules, ", "), task,
	)

	if err := ctrl.Run(ctx, prompt); err != nil {
		if output.Len() > 0 {
			return output.String()
		}
		return fmt.Sprintf("error: %v", err)
	}
	return output.String()
}

func runExecutor(module string, task string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	var output strings.Builder
	sink := &collectSink{buf: &output}

	ctrl, err := boot.Build(ctx, boot.Options{Sink: sink})
	if err != nil {
		return fmt.Sprintf("boot error: %v", err)
	}
	defer ctrl.Close()

	prompt := fmt.Sprintf(
		"You are the Executor for module '%s'. Execute: %s. "+
			"Read files, write code, run tests.",
		module, task,
	)

	if err := ctrl.Run(ctx, prompt); err != nil {
		if output.Len() > 0 {
			return output.String()
		}
		return fmt.Sprintf("error: %v", err)
	}
	return output.String()
}

// ==========================================================================
// Event sinks
// ==========================================================================

type textSink struct{}

func (s *textSink) Emit(ev event.Event) {
	if ev.Kind == event.Text {
		fmt.Print(ev.Text)
	} else if ev.Kind == event.Reasoning {
		fmt.Print("[💭]")
	} else if ev.Kind == event.ToolDispatch {
		fmt.Printf("\n🔧 %s", ev.Tool.Name)
	} else if ev.Kind == event.ToolResult {
		fmt.Printf(" ✓")
	}
}

type collectSink struct {
	buf *strings.Builder
}

func (s *collectSink) Emit(ev event.Event) {
	if ev.Kind == event.Text {
		s.buf.WriteString(ev.Text)
	}
}
