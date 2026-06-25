package cli

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"reasonix_gr/internal/event"
	"reasonix_gr/internal/evergreen/federation"
)

func ceoCommand(rest []string) int {
	fleet := setupFleet()
	if fleet == nil {
		return 1
	}
	defer fleet.Save()

	ceo := federation.NewCEO(fleet, event.Discard)

	fmt.Println("╔══════════════════════════════════════╗")
	fmt.Println("║    Evergreen Fleet CEO               ║")
	sts := fleet.Status()
	fmt.Printf("║    %d agents, %.0fK context capacity   ║\n", sts.TotalAgents, float64(sts.TotalAgents)*131)
	fmt.Println("║    /agents /watch /unwatch /exit     ║")
	fmt.Println("╚══════════════════════════════════════╝")
	fmt.Println()

	ctx := context.Background()
	type pendingReply struct {
		resp *federation.CEOResponse
		err  error
	}
	replyCh := make(chan pendingReply, 1)
	busy := false
	monitor := fleet.Monitor()
	watching := ""
	lastStatus := ""

	// Background scanner → channel
	lineCh := make(chan string, 32)
	go func() {
		sc := bufio.NewScanner(os.Stdin)
		for sc.Scan() {
			lineCh <- strings.TrimSpace(sc.Text())
		}
		close(lineCh)
	}()

	readInput := func(timeout time.Duration) string {
		select {
		case line := <-lineCh:
			return line
		case <-time.After(timeout):
			return ""
		}
	}

	for {
		if watching != "" {
			// ── Watch mode: live refresh, Enter = back to CEO ──
			fmt.Print("\033[2J\033[H")
			fmt.Print(monitor.RenderAgentOutput(watching, 40))
			fmt.Print("[Enter=back to CEO | /exit=quit]\n")

			select {
			case reply := <-replyCh:
				busy = false
				watching = ""
				fmt.Print("\033[2J\033[H")
				fmt.Print(renderConversation(reply.resp, reply.err))
				time.Sleep(800 * time.Millisecond)
				continue

			case input := <-lineCh:
				lower := strings.ToLower(input)
				switch {
				case lower == "/exit" || lower == "/quit" || lower == "/q":
					fmt.Println("CEO: Goodbye!")
					return 0
				case lower == "" || lower == "/unwatch":
					// Enter or /unwatch → back to CEO
					watching = ""
					fmt.Print("\033[2J\033[H")
					fmt.Println("Back to CEO.")
				case strings.HasPrefix(lower, "/watch"):
					parts := strings.Fields(input)
					if len(parts) < 2 {
						fmt.Print("\033[2J\033[H")
						fmt.Println("Usage: /watch <N> or /watch <agent-id>")
						time.Sleep(1 * time.Second)
					} else if a := monitor.FindAgent(parts[1]); a != nil {
						watching = a.ID
					}
				}

			case <-time.After(500 * time.Millisecond):
				// timeout → refresh
			}
			continue
		}

		// ── Normal mode ──
		s := monitor.StatusBar()
		if s != lastStatus || busy {
			lastStatus = s
			if busy {
				fmt.Printf("[%s] ⏳ CEO working...\n", s)
			} else {
				fmt.Printf("[%s]\n", s)
			}
		}

		// Check CEO reply
		select {
		case reply := <-replyCh:
			busy = false
			if reply.err != nil {
				fmt.Printf("CEO: error - %v\n\n", reply.err)
			}
			if reply.resp != nil {
				fmt.Printf("CEO: %s\n\n", reply.resp.Answer)
			}
		default:
		}

		fmt.Print("You: ")
		input := readInput(30 * time.Second)
		if input == "" {
			continue
		}

		lower := strings.ToLower(input)
		switch {
		case lower == "/exit" || lower == "/quit" || lower == "/q":
			fmt.Println("CEO: Goodbye!")
			return 0
		case strings.HasPrefix(lower, "/watch"):
			parts := strings.Fields(input)
			if len(parts) < 2 {
				fmt.Println("Usage: /watch <N> or /watch <agent-id>")
				continue
			}
			if a := monitor.FindAgent(parts[1]); a != nil {
				watching = a.ID
				fmt.Print("\033[2J\033[H")
			} else {
				fmt.Printf("Not found: %s\n", parts[1])
			}
			continue
		case lower == "/agents":
			fmt.Print(monitor.RenderDashboard())
			continue
		case lower == "/status" || lower == "/s":
			input = "show fleet status"
		case lower == "/help" || lower == "/h":
			fmt.Println("/agents /watch <N> /unwatch /status /help /exit")
			continue
		}

		busy = true
		fmt.Println("  Delegating...")
		go func(msg string) {
			resp, err := ceo.Chat(ctx, msg)
			replyCh <- pendingReply{resp, err}
		}(input)
	}
}

// renderConversation shows the CEO's last dialogue.
func renderConversation(resp *federation.CEOResponse, err error) string {
	var b strings.Builder
	b.WriteString("╔══════════════════════════════════════╗\n")
	b.WriteString("║         CEO Conversation              ║\n")
	b.WriteString("╚══════════════════════════════════════╝\n\n")
	if err != nil {
		b.WriteString(fmt.Sprintf("❌ error: %v\n", err))
	} else if resp != nil {
		b.WriteString(fmt.Sprintf("👤 You: %s\n\n", resp.UserMessage))
		b.WriteString(fmt.Sprintf("🤖 CEO: %s\n", resp.Answer))
		if resp.AgentsInvoked > 0 {
			b.WriteString(fmt.Sprintf("\n   ↳ %d specialist(s) consulted\n", resp.AgentsInvoked))
		}
	}
	return b.String()
}
