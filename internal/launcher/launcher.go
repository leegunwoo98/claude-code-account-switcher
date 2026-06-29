// Package launcher starts Claude Code authenticated as a chosen subscription and
// isolated to its own config dir. The platform-specific execClaude either
// replaces the process (Unix) or runs claude as a child (Windows).
package launcher

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/leegunwoo98/claude-code-account-switcher/internal/credstore"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/isolation"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/paths"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/registry"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/usage"
)

// scrubVars are competing credentials unset so subprocesses, hooks, and MCP
// servers can't inherit a different account's auth.
var scrubVars = []string{
	"ANTHROPIC_API_KEY",
	"ANTHROPIC_AUTH_TOKEN",
	"ANTHROPIC_BASE_URL",
	"CLAUDE_CODE_USE_BEDROCK",
	"CLAUDE_CODE_USE_VERTEX",
	"CLAUDE_CODE_USE_FOUNDRY",
}

// Launch starts claude as the given account.
func Launch(acct registry.Account, args []string) error {
	token, err := credstore.Get(acct.Service)
	if err != nil {
		return fmt.Errorf("read token: %w", err)
	}
	if token == "" {
		fmt.Fprintf(os.Stderr, "No token found for %s.\nRun: claude-accounts\n", acct.Label)
		return fmt.Errorf("no token for %s", acct.Slug)
	}

	configDir, err := isolation.Build(acct.Slug)
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: account isolation failed (%v); launching unisolated\n", err)
		configDir = ""
	}

	if pct, ok := usage.FiveHourNearLimit(acct.Slug, 85, time.Now().Unix()); ok {
		fmt.Fprintf(os.Stderr, "Note: this subscription was at %.0f%% of its 5-hour limit a moment ago.\n", pct)
	}

	bin := claudePath()
	argv := []string{bin}
	if s := paths.UsageSettings(); readable(s) {
		argv = append(argv, "--settings", s)
	}
	// Naming the session surfaces the account in the resume picker and terminal
	// title, but it replaces Claude's auto-generated description there. The
	// status line already shows the account in-session, so opt in explicitly.
	if os.Getenv("CLAUDE_SUBSCRIPTION_NAME_SESSIONS") != "" && !hasExplicitName(args) {
		argv = append(argv, "--name", acct.Label)
	}
	argv = append(argv, args...)

	fmt.Fprintf(os.Stderr, "Starting Claude with subscription: %s\n", acct.Label)
	return execClaude(bin, argv, buildEnv(token, acct, configDir))
}

func buildEnv(token string, acct registry.Account, configDir string) []string {
	skip := map[string]bool{
		"CLAUDE_CODE_OAUTH_TOKEN":          true,
		"CLAUDE_SUBSCRIPTION_SLUG":         true,
		"CLAUDE_SUBSCRIPTION_LABEL":        true,
		"CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": true,
	}
	for _, k := range scrubVars {
		skip[k] = true
	}
	if configDir != "" {
		skip["CLAUDE_CONFIG_DIR"] = true
	}

	var env []string
	for _, kv := range os.Environ() {
		if i := strings.IndexByte(kv, '='); i >= 0 && skip[kv[:i]] {
			continue
		}
		env = append(env, kv)
	}
	env = append(env,
		"CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1",
		"CLAUDE_CODE_OAUTH_TOKEN="+token,
		"CLAUDE_SUBSCRIPTION_SLUG="+acct.Slug,
		"CLAUDE_SUBSCRIPTION_LABEL="+acct.Label,
	)
	if configDir != "" {
		env = append(env, "CLAUDE_CONFIG_DIR="+configDir)
	}
	return env
}

func claudePath() string {
	if p, err := exec.LookPath("claude"); err == nil {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "bin", "claude")
}

func readable(p string) bool {
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	_ = f.Close()
	return true
}

// hasExplicitName matches the zsh detector: a --name/--name=/-n/-nVALUE before
// any "--" terminator means the user named the session themselves.
func hasExplicitName(args []string) bool {
	for _, a := range args {
		if a == "--" {
			return false
		}
		switch {
		case a == "--name", a == "-n", strings.HasPrefix(a, "--name="):
			return true
		case strings.HasPrefix(a, "-n") && len(a) > 2:
			return true
		}
	}
	return false
}
