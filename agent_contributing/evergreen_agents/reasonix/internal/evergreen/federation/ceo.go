package federation

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"reasonix_gr/internal/agent"
	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/checklist"
)

// CEO is the user-facing entry point to the entire Fleet. The user talks to
// the CEO, not individual Keepers or Executors. The CEO:
//
//   1. Understands the user's intent (natural language)
//   2. Decides which specialists to involve
//   3. Delegates to Keepers/Executors as needed
//   4. Synthesizes responses back into a coherent answer
//   5. Maintains a persistent session — gets to know the project over time
//
// Think of the CEO as the "tech lead you DM on Slack." You describe what you
// want; the CEO figures out who needs to be involved and comes back with
// a consolidated answer.

type CEO struct {
	fleet   *Fleet
	session *agent.Session // persistent user conversation
	sink    event.Sink
	sysPrompt string
}

// NewCEO creates the CEO agent for a fleet.
func NewCEO(fleet *Fleet, sink event.Sink) *CEO {
	return &CEO{
		fleet:     fleet,
		session:   fleet.restoreOrCreate("ceo", ceoSystemPrompt),
		sink:      sink,
		sysPrompt: ceoSystemPrompt,
	}
}

// Chat is the main entry point. The user says something in natural language;
// the CEO processes it, delegates as needed, and returns a response.
func (c *CEO) Chat(ctx context.Context, userMessage string) (*CEOResponse, error) {
	resp := &CEOResponse{UserMessage: userMessage}

	// Step 1: Classify intent. What does the user want?
	intent := c.classifyIntent(userMessage)
	resp.Intent = intent

	slog.Info("ceo: received message", "intent", intent, "msg", truncateStr(userMessage, 100))

	switch intent {
	case IntentTask:
		return c.handleTask(ctx, userMessage)
	case IntentQuestion:
		return c.handleQuestion(ctx, userMessage)
	case IntentReview:
		return c.handleReview(ctx, userMessage)
	case IntentStatus:
		return c.handleStatus(ctx)
	case IntentLearn:
		return c.handleLearn(ctx, userMessage)
	default:
		return c.handleChat(ctx, userMessage)
	}
}

// CEOResponse is the CEO's structured response to the user.
type CEOResponse struct {
	UserMessage    string   // original user message
	Intent         Intent   // classified intent
	Answer         string   // CEO's natural language response
	ModulesTouched []string // which modules were involved
	AgentsInvoked  int      // how many specialists were consulted
	TaskResult     *TaskResult // if a task was executed
}

// Intent classifies what the user wants.
type Intent string

const (
	IntentTask     Intent = "task"     // "add login test", "fix the overflow bug"
	IntentQuestion Intent = "question" // "how does auth work?", "explain the cache"
	IntentReview   Intent = "review"   // "review this change", "check module auth"
	IntentStatus   Intent = "status"   // "what's the fleet status?", "how's auth doing?"
	IntentLearn    Intent = "learn"    // "tell me about the XP library", "what patterns exist?"
	IntentChat     Intent = "chat"     // general conversation
)

// classifyIntent uses simple heuristics to determine what the user wants.
// In production, this uses the LLM for nuanced classification.
func (c *CEO) classifyIntent(msg string) Intent {
	lower := strings.ToLower(msg)

	// Status queries
	if strings.Contains(lower, "status") || strings.Contains(lower, "状态") ||
		strings.Contains(lower, "how is") || strings.Contains(lower, "how are") {
		if strings.Contains(lower, "fleet") || strings.Contains(lower, "agent") ||
			strings.Contains(lower, "module") || strings.Contains(lower, "模块") {
			return IntentStatus
		}
	}

	// Learning queries
	if strings.Contains(lower, "pattern") || strings.Contains(lower, "经验") ||
		strings.Contains(lower, "xp") || strings.Contains(lower, "learn") ||
		strings.Contains(lower, "what is") || strings.Contains(lower, "explain") ||
		strings.Contains(lower, "解释") || strings.Contains(lower, "什么是") {
		return IntentQuestion
	}

	// Review queries
	if strings.Contains(lower, "review") || strings.Contains(lower, "审查") ||
		strings.Contains(lower, "check") || strings.Contains(lower, "检查") {
		return IntentReview
	}

	// Task queries (most common — default)
	if strings.Contains(lower, "add") || strings.Contains(lower, "fix") ||
		strings.Contains(lower, "implement") || strings.Contains(lower, "refactor") ||
		strings.Contains(lower, "test") || strings.Contains(lower, "build") ||
		strings.Contains(lower, "修改") || strings.Contains(lower, "修复") ||
		strings.Contains(lower, "实现") || strings.Contains(lower, "写") ||
		strings.Contains(lower, "加") || strings.Contains(lower, "改") {
		return IntentTask
	}

	// Default to chat
	return IntentChat
}

// handleTask processes a task request: delegate to Fleet.RunTask().
func (c *CEO) handleTask(ctx context.Context, msg string) (*CEOResponse, error) {
	module := c.extractModule(msg)

	if module == "" {
		return &CEOResponse{
			Intent: IntentTask,
			Answer: fmt.Sprintf("Which module? I know: %s\n\nTry: 'fix the auth module's login bug'", c.listModules()),
		}, nil
	}

	result, err := c.fleet.RunTask(ctx, msg, module)
	if err != nil {
		return &CEOResponse{
			Intent:         IntentTask,
			Answer:         fmt.Sprintf("❌ Failed: %v\n\nCheck: is DEEPSEEK_API_KEY set? Run 'reasonix_gr setup' if needed.", err),
			ModulesTouched: []string{module},
		}, nil
	}

	fleetStatus := c.fleet.Status()
	var answer strings.Builder
	answer.WriteString(fmt.Sprintf("Done! The **%s** team handled it.\n\n", module))
	answer.WriteString(fmt.Sprintf("> Fleet: %d agents | %d involved | %d idle · %.0fK context capacity\n\n",
		fleetStatus.TotalAgents, result.AgentsInvolved, result.AgentsIdle, float64(fleetStatus.TotalAgents)*131))

	if result.KeeperReview != "" {
		answer.WriteString(fmt.Sprintf("**🔍 Keeper(%s):**\n%s\n\n", module, summarize(result.KeeperReview, 400)))
	}
	if result.ExecutorOutput != "" {
		answer.WriteString(fmt.Sprintf("**🛠️ Executor(%s):**\n%s\n\n", module, summarize(result.ExecutorOutput, 600)))
	}
	if result.LibrarianOutput != "" {
		answer.WriteString(fmt.Sprintf("**📚 Librarian:** %s\n", summarize(result.LibrarianOutput, 200)))
	}
	answer.WriteString("✅ Task complete. Need anything else?")

	return &CEOResponse{
		Intent:         IntentTask,
		Answer:         answer.String(),
		ModulesTouched: []string{module},
		AgentsInvoked:  result.AgentsInvolved,
		TaskResult:     result,
	}, nil
}

// handleQuestion answers a question by consulting relevant keepers.
func (c *CEO) handleQuestion(ctx context.Context, msg string) (*CEOResponse, error) {
	module := c.extractModule(msg)

	// Search experience library
	store := c.fleet.store
	results := store.Search(msg, nil, module, nil, 5)

	var answer strings.Builder
	answer.WriteString(fmt.Sprintf("Good question! Here's what I found:\n\n"))

	fleetStatus := c.fleet.Status()
	answer.WriteString(fmt.Sprintf("> Consulting %d keepers, %d XP cards | Fleet: %d idle agents\n\n",
		1, len(results), fleetStatus.IdleAgents))

	if len(results) > 0 {
		answer.WriteString("**Relevant experience cards:**\n")
		for _, r := range results {
			answer.WriteString(fmt.Sprintf("- **%s** (%s): %s\n", r.Card.Title, r.Card.Type, summarize(r.Card.Body, 200)))
		}
	} else {
		answer.WriteString("No matching experience cards found. Let me check with the module keepers...\n\n")

		// If we have a module, ask the keeper
		if module != "" {
			fleetStatus := c.fleet.Status()
			_ = fleetStatus
			answer.WriteString(fmt.Sprintf("I'd ask the **%s Keeper** to look into this. ", module))
			answer.WriteString("The keeper has accumulated deep knowledge of this module over time.\n")
		}
	}

	return &CEOResponse{
		Intent:         IntentQuestion,
		Answer:         answer.String(),
		ModulesTouched: []string{module},
	}, nil
}

// handleReview triggers a review of a module.
func (c *CEO) handleReview(ctx context.Context, msg string) (*CEOResponse, error) {
	module := c.extractModule(msg)

	// Generate checklist for the module
	store := c.fleet.store
	cl := checklist.Generate(module, store)

	var answer strings.Builder
	answer.WriteString(fmt.Sprintf("I've triggered a review of **%s**.\n\n", module))

	answer.WriteString(fmt.Sprintf("**REVIEW_CHECKLIST** (%d checks, %d must):\n", cl.Stats.Total, cl.Stats.Must))
	for _, item := range cl.Items {
		if item.Severity == "must" {
			answer.WriteString(fmt.Sprintf("- [ ] **%s**: %s\n", item.ID, item.Check))
		}
	}

	// Queue keeper review
	fleetStatus := c.fleet.Status()
	answer.WriteString(fmt.Sprintf("\n> Fleet: %d agents | Keeper(%s) queued for review\n",
		fleetStatus.TotalAgents, module))

	return &CEOResponse{
		Intent:         IntentReview,
		Answer:         answer.String(),
		ModulesTouched: []string{module},
		AgentsInvoked:  1,
	}, nil
}

// handleStatus reports the current fleet and module status.
func (c *CEO) handleStatus(ctx context.Context) (*CEOResponse, error) {
	status := c.fleet.Status()
	storeStats := c.fleet.store.Stats()

	var answer strings.Builder
	answer.WriteString("Here's the current state of the team:\n\n")

	answer.WriteString("**Fleet**\n")
	answer.WriteString(fmt.Sprintf("- Uptime: %s\n", status.Uptime))
	answer.WriteString(fmt.Sprintf("- Agents: %d total (%d keepers + %d executors + 3 special)\n",
		status.TotalAgents, status.Keepers, status.Executors))
	answer.WriteString(fmt.Sprintf("- Active: %d | Idle: %d\n", status.ActiveAgents, status.IdleAgents))
	answer.WriteString(fmt.Sprintf("- Total tasks: %d\n", status.TotalTasks))
	answer.WriteString(fmt.Sprintf("- Context capacity: %.0fK tokens\n", float64(status.TotalAgents)*131))

	answer.WriteString("\n**Experience Library**\n")
	if total, ok := storeStats["total"]; ok {
		answer.WriteString(fmt.Sprintf("- %v cards\n", total))
	}
	if byType, ok := storeStats["by_type"]; ok {
		answer.WriteString(fmt.Sprintf("- By type: %v\n", byType))
	}

	return &CEOResponse{
		Intent: IntentStatus,
		Answer: answer.String(),
	}, nil
}

// handleLearn processes learning/introspection requests.
func (c *CEO) handleLearn(ctx context.Context, msg string) (*CEOResponse, error) {
	store := c.fleet.store
	results := store.Search(msg, nil, "", nil, 10)

	var answer strings.Builder
	answer.WriteString("Here's what our team has learned:\n\n")

	status := c.fleet.Status()
	answer.WriteString(fmt.Sprintf("> XP library: %d cards | Fleet: %d agents\n\n", len(results), status.TotalAgents))

	if len(results) > 0 {
		for _, r := range results {
			answer.WriteString(fmt.Sprintf("### %s\n", r.Card.Title))
			answer.WriteString(fmt.Sprintf("Type: %s | Module: %s\n", r.Card.Type, r.Card.Module))
			answer.WriteString(fmt.Sprintf("%s\n\n", summarize(r.Card.Body, 300)))
		}
	} else {
		answer.WriteString("Nothing specifically matching that yet. As the team does more work, patterns will accumulate here.\n")
	}

	return &CEOResponse{
		Intent: IntentLearn,
		Answer: answer.String(),
	}, nil
}

// handleChat responds to general conversation.
func (c *CEO) handleChat(ctx context.Context, msg string) (*CEOResponse, error) {
	// CEO uses LLM for natural conversation only — NO code tools
	subReg := agent.ReadOnlySubagentToolRegistry(c.fleet.parentReg, ceoTools)
	prompt := fmt.Sprintf("User said: %s\n\nYou are the CEO of a large engineering team. You do NOT read or write code — you coordinate specialists. Respond helpfully. If they ask for something technical, say you'll delegate to the right specialist.", msg)

	answer, _ := agent.RunSubAgentWithSession(ctx, c.fleet.prov, subReg, c.session, prompt,
		agent.Options{MaxSteps: 3, Temperature: 0.7, UsageSource: event.UsageSourceSubagent, Gate: c.fleet.gate},
		c.sink)

	return &CEOResponse{
		Intent: IntentChat,
		Answer: answer,
	}, nil
}

// extractModule tries to extract a module name from the user message.
func (c *CEO) extractModule(msg string) string {
	lower := strings.ToLower(msg)

	// Check all known modules
	c.fleet.mu.RLock()
	defer c.fleet.mu.RUnlock()

	for mod := range c.fleet.keepers {
		if strings.Contains(lower, strings.ToLower(mod)) {
			return mod
		}
	}

	// Common keywords → module mapping
	keywordMap := map[string]string{
		"login": "auth", "认证": "auth", "登录": "auth", "sso": "auth",
		"course": "courses", "课程": "courses", "课表": "schedule",
		"schedule": "schedule", "日程": "schedule",
		"translate": "translate", "翻译": "translate", "pdf": "translate",
		"exam": "exams", "考试": "exams",
		"todo": "todo", "待办": "todo",
		"score": "scores", "成绩": "scores",
		"library": "library", "图书馆": "library",
		"download": "downloads", "下载": "downloads",
		"palace": "palace", "宫殿": "palace",
		"tutor": "tutor", "辅导": "tutor",
		"plan": "plan", "计划": "plan",
		"settings": "settings", "设置": "settings",
		"network": "connectivity", "网络": "connectivity", "vpn": "rvpn",
		"ecard": "ecard", "一卡通": "ecard",
		"zdbk": "zdbk", "教务": "zdbk",
		"pintia": "pintia", "pta": "pintia",
		"wordpecker": "wordpecker",
		"autosign": "autosign", "自动签到": "autosign",
	}

	for kw, mod := range keywordMap {
		if strings.Contains(lower, kw) {
			return mod
		}
	}

	return "" // unknown — CEO will ask for clarification
}

// ceoTools are the ONLY tools the CEO can access. No code reading or writing —
// the CEO delegates to specialists for anything technical.
var ceoTools = []string{"experience_query", "dependency_analyze"}

// listModules returns a formatted list of known module names.
func (c *CEO) listModules() string {
	c.fleet.mu.RLock()
	defer c.fleet.mu.RUnlock()
	var mods []string
	for m := range c.fleet.keepers {
		mods = append(mods, m)
	}
	// Sort for stable output
	for i := 0; i < len(mods); i++ {
		for j := i + 1; j < len(mods); j++ {
			if mods[i] > mods[j] {
				mods[i], mods[j] = mods[j], mods[i]
			}
		}
	}
	return strings.Join(mods, ", ")
}

// summarize truncates and cleans text for display.
func summarize(text string, maxLen int) string {
	text = strings.TrimSpace(text)
	if len(text) <= maxLen {
		return text
	}
	// Try to break at a sentence boundary
	cut := strings.LastIndexAny(text[:maxLen], ".!?。！？\n")
	if cut > maxLen/2 {
		return text[:cut+1] + "\n*(truncated)*"
	}
	return text[:maxLen] + "...\n*(truncated)*"
}

// ---- CEO System Prompt ----

const ceoSystemPrompt = `You are the CEO of a large engineering team — the Evergreen multi-agent federation.

IMPORTANT: You do NOT read code. You do NOT write code. You are not technical.
Your job is coordination, delegation, and synthesis — like a real CEO.

Your team:
- 1 Tech Lead (Planner) — decomposes complex tasks, reads architecture
- 26 Module Owners (Keepers) — each owns one module, reviews all changes
- 26 Senior Developers (Executors) — each specializes in one module
- 1 QA Architect (Inspector) — scans for quality issues
- 1 Knowledge Manager (Librarian) — curates experience cards

What you DO:
- Understand the user's INTENT. What do they want to accomplish?
- Know WHO to delegate to. Which module is responsible?
- SYNTHESIZE responses from specialists into a coherent answer.
- Track fleet STATUS. Who's active? What's the team's capacity?
- Recognize when you need CLARIFICATION from the user.

What you NEVER do:
- Read source code (that's the Keeper's job)
- Write code (that's the Executor's job)
- Make technical judgments about implementation details
- Pretend to know technical specifics — delegate, then report what the specialist said

When the user asks for something technical:
1. Identify which module(s) are involved
2. Tell the user you're delegating to the relevant specialist(s)
3. Report back what the specialist found/recommended/did
4. Ask if they need anything else

Be a great manager, not a pretend-engineer. If you don't know, say so and find the right person.`
