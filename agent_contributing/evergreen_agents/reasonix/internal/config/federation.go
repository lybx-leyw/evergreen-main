package config

// ---------------------------------------------------------------------------
// Evergreen Federation configuration (YAML-compatible, extends reasonix TOML config)
// ---------------------------------------------------------------------------

// FederationConfig holds all Evergreen multi-agent federation settings.
// These are loaded from the evergreen_agents.yaml project-level config file
// and merged into the reasonix Config.
type FederationConfig struct {
	// MaxDebateRounds caps the number of debate rounds between agents (default 3).
	MaxDebateRounds int `yaml:"max_debate_rounds" toml:"max_debate_rounds"`

	// ModuleRegistryPath is the path to module_registry.yaml relative to workspace root.
	ModuleRegistryPath string `yaml:"module_registry_path" toml:"module_registry_path"`

	// ExperienceDir is the path to the experience cards directory.
	ExperienceDir string `yaml:"experience_dir" toml:"experience_dir"`

	// Credit holds credit scoring configuration.
	Credit CreditConfig `yaml:"credit" toml:"credit"`

	// LLMRouting configures the two-tier LLM model selection.
	LLMRouting LLMRoutingConfig `yaml:"llm_routing" toml:"llm_routing"`

	// MergeQueue configures serialized CI-gated merging.
	MergeQueue MergeQueueConfig `yaml:"merge_queue" toml:"merge_queue"`

	// FeatureFlags gates experimental federation features.
	FeatureFlags map[string]bool `yaml:"feature_flags" toml:"feature_flags"`

	// SLO holds service-level objective configuration.
	SLO SLOConfig `yaml:"slo" toml:"slo"`
}

// CreditConfig holds credit scoring weights and thresholds.
type CreditConfig struct {
	// InitialScore is the starting credit score for new agents (default 100).
	InitialScore float64 `yaml:"initial_score" toml:"initial_score"`
	// MinExecuteScore is the minimum composite score to execute tasks (default 50).
	MinExecuteScore float64 `yaml:"min_execute_score" toml:"min_execute_score"`
	// MinReviewScore is the minimum composite score to review code (default 60).
	MinReviewScore float64 `yaml:"min_review_score" toml:"min_review_score"`
	// Weights maps dimension names to their weight in the composite score.
	Weights map[string]float64 `yaml:"weights" toml:"weights"`
}

// LLMRoutingConfig configures two-tier LLM model selection per agent role.
type LLMRoutingConfig struct {
	// DeepThinking configures the deep-thinking model (planner, librarian).
	DeepThinking LLMTierConfig `yaml:"deep_thinking" toml:"deep_thinking"`
	// QuickThinking configures the quick-thinking model (keeper, executor, inspector).
	QuickThinking LLMTierConfig `yaml:"quick_thinking" toml:"quick_thinking"`
}

// LLMTierConfig holds a single LLM tier's configuration.
type LLMTierConfig struct {
	// Provider is the provider name (e.g. "deepseek", "openai").
	Provider string `yaml:"provider" toml:"provider"`
	// Model is the model name (e.g. "deepseek-v4-pro").
	Model string `yaml:"model" toml:"model"`
	// Temperature controls response randomness.
	Temperature float64 `yaml:"temperature" toml:"temperature"`
	// MaxSteps caps the number of tool-calling turns.
	MaxSteps int `yaml:"max_steps" toml:"max_steps"`
}

// MergeQueueConfig configures the serial merge queue.
type MergeQueueConfig struct {
	// Enabled toggles the merge queue (default true).
	Enabled bool `yaml:"enabled" toml:"enabled"`
	// BatchSize is how many CLs to batch together (default 5).
	BatchSize int `yaml:"batch_size" toml:"batch_size"`
	// CITimeoutMinutes is the CI timeout in minutes (default 30).
	CITimeoutMinutes int `yaml:"ci_timeout_minutes" toml:"ci_timeout_minutes"`
	// AutoRevertOnFailure reverts the batch if CI fails (default true).
	AutoRevertOnFailure bool `yaml:"auto_revert_on_failure" toml:"auto_revert_on_failure"`
}

// SLOConfig holds service-level objective configuration.
type SLOConfig struct {
	// ErrorBudgetPercent is the monthly error budget percentage (default 1.0%).
	ErrorBudgetPercent float64 `yaml:"error_budget_percent" toml:"error_budget_percent"`
	// MaxTasksPerHour caps agent task throughput.
	MaxTasksPerHour int `yaml:"max_tasks_per_hour" toml:"max_tasks_per_hour"`
	// ResponseTimeTargetMs is the target response time in milliseconds.
	ResponseTimeTargetMs int `yaml:"response_time_target_ms" toml:"response_time_target_ms"`
}

// DefaultFederationConfig returns the built-in federation defaults.
// Mirrors Python config/default_config.yaml.
func DefaultFederationConfig() FederationConfig {
	return FederationConfig{
		MaxDebateRounds:    3,
		ModuleRegistryPath: "agent_contributing/evergreen_agents/config/module_registry.yaml",
		ExperienceDir:      "agent_contributing/experiences",
		Credit: CreditConfig{
			InitialScore:    100.0,
			MinExecuteScore: 50.0,
			MinReviewScore:  60.0,
			Weights: map[string]float64{
				"code_quality":         0.25,
				"test_quality":         0.20,
				"review_accuracy":      0.20,
				"experience_quality":   0.15,
				"error_budget_respect": 0.10,
				"collaboration":        0.10,
			},
		},
		LLMRouting: LLMRoutingConfig{
			DeepThinking: LLMTierConfig{
				Provider:    "deepseek",
				Model:       "deepseek-v4-pro",
				Temperature: 0.3,
				MaxSteps:    30,
			},
			QuickThinking: LLMTierConfig{
				Provider:    "deepseek",
				Model:       "deepseek-v4-flash",
				Temperature: 0.3,
				MaxSteps:    30,
			},
		},
		MergeQueue: MergeQueueConfig{
			Enabled:             true,
			BatchSize:           5,
			CITimeoutMinutes:    30,
			AutoRevertOnFailure: true,
		},
		FeatureFlags: map[string]bool{
			"require_flag_for_new_features": true,
		},
		SLO: SLOConfig{
			ErrorBudgetPercent:   1.0,
			MaxTasksPerHour:      10,
			ResponseTimeTargetMs: 5000,
		},
	}
}
