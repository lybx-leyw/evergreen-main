// Command reasonix is a config- and plugin-driven coding agent CLI.
package main

import (
	"os"

	"reasonix_gr/internal/cli"

	// Blank imports wire compile-time built-ins into their registries.
	_ "reasonix_gr/internal/provider/anthropic"
	_ "reasonix_gr/internal/provider/openai"
	_ "reasonix_gr/internal/tool/builtin"
)

// version is injected at build time via -ldflags "-X main.version=...".
var version = "dev"

func main() {
	os.Exit(cli.Run(os.Args[1:], version))
}
