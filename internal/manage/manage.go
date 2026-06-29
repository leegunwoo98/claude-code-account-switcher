// Package manage adds, refreshes, and removes subscriptions: it runs
// `claude setup-token`, stores the resulting token in the credential store, and
// updates the registry.
package manage

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/leegunwoo98/claude-code-account-switcher/internal/credstore"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/paths"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/registry"
)

// Add registers a new subscription interactively.
func Add() error {
	in := bufio.NewReader(os.Stdin)

	name, err := promptLine(in, "Subscription display name: ")
	if err != nil {
		return err
	}
	if name == "" || strings.ContainsAny(name, "\t\n") {
		return errors.New("display name must be non-empty and free of tabs and newlines")
	}

	suggested := Slugify(name)
	slug, err := promptLine(in, fmt.Sprintf("Command suffix, without claude- [%s]: ", suggested))
	if err != nil {
		return err
	}
	if slug == "" {
		slug = suggested
	}
	slug = strings.TrimPrefix(slug, "claude-")
	if !registry.ValidSlug(slug) {
		return errors.New("suffix must use lowercase letters, numbers, and internal hyphens only")
	}
	if _, ok := registry.Find(slug); ok {
		return fmt.Errorf("subscription %q already exists — use 'claude-accounts refresh %s'", slug, slug)
	}

	service := registry.ServiceFor(slug)
	token, err := setupToken(in, name)
	if err != nil {
		return err
	}
	if err := credstore.Set(service, token); err != nil {
		return fmt.Errorf("store token: %w", err)
	}
	if err := registry.Append(registry.Account{Slug: slug, Label: name, Service: service}); err != nil {
		return err
	}
	clearUsage(slug)
	fmt.Printf("Stored %s. Launch with: claude-%s\n", name, slug)
	return nil
}

// Refresh replaces the token for an existing subscription.
func Refresh(slug string) error {
	acct, ok := registry.Find(slug)
	if !ok {
		return fmt.Errorf("unknown subscription: %s", slug)
	}
	token, err := setupToken(bufio.NewReader(os.Stdin), acct.Label)
	if err != nil {
		return err
	}
	if err := credstore.Set(acct.Service, token); err != nil {
		return fmt.Errorf("store token: %w", err)
	}
	clearUsage(slug)
	fmt.Printf("Refreshed token for %s.\n", acct.Label)
	return nil
}

// Remove deletes a subscription's token and registry entry.
func Remove(slug string) error {
	acct, ok := registry.Find(slug)
	if !ok {
		return fmt.Errorf("unknown subscription: %s", slug)
	}
	ans, _ := promptLine(bufio.NewReader(os.Stdin), fmt.Sprintf("Remove %s and its token? [y/N] ", acct.Label))
	if strings.ToLower(ans) != "y" {
		fmt.Println("Kept.")
		return nil
	}
	_ = credstore.Delete(acct.Service)
	if err := registry.Remove(slug); err != nil {
		return err
	}
	clearUsage(slug)
	fmt.Printf("Removed %s.\n", acct.Label)
	return nil
}

// Edit changes a subscription's display name and/or command suffix. Renaming the
// suffix moves the token to the new Keychain service and the cached usage; the
// stale claude-<slug> command is pruned by the manager's command sync.
func Edit(slug string) error {
	acct, ok := registry.Find(slug)
	if !ok {
		return fmt.Errorf("unknown subscription: %s", slug)
	}
	in := bufio.NewReader(os.Stdin)

	name, err := promptLine(in, fmt.Sprintf("Display name [%s]: ", acct.Label))
	if err != nil {
		return err
	}
	if name == "" {
		name = acct.Label
	}
	if strings.ContainsAny(name, "\t\n") {
		return errors.New("display name must be free of tabs and newlines")
	}

	newSlug, err := promptLine(in, fmt.Sprintf("Command suffix, without claude- [%s]: ", acct.Slug))
	if err != nil {
		return err
	}
	if newSlug == "" {
		newSlug = acct.Slug
	}
	newSlug = strings.TrimPrefix(newSlug, "claude-")
	if !registry.ValidSlug(newSlug) {
		return errors.New("suffix must use lowercase letters, numbers, and internal hyphens only")
	}

	if newSlug == acct.Slug {
		if name == acct.Label {
			fmt.Println("No changes.")
			return nil
		}
		return rewrite(acct.Slug, registry.Account{Slug: acct.Slug, Label: name, Service: acct.Service})
	}

	if _, exists := registry.Find(newSlug); exists {
		return fmt.Errorf("subscription %q already exists", newSlug)
	}
	newService := registry.ServiceFor(newSlug)
	if token, _ := credstore.Get(acct.Service); token != "" {
		if err := credstore.Set(newService, token); err != nil {
			return fmt.Errorf("move token: %w", err)
		}
		_ = credstore.Delete(acct.Service)
	}
	if err := rewrite(acct.Slug, registry.Account{Slug: newSlug, Label: name, Service: newService}); err != nil {
		return err
	}
	_ = os.Rename(
		filepath.Join(paths.UsageDir(), acct.Slug+".json"),
		filepath.Join(paths.UsageDir(), newSlug+".json"),
	)
	fmt.Printf("Updated %s. Launch with: claude-%s\n", name, newSlug)
	return nil
}

func rewrite(oldSlug string, a registry.Account) error {
	if err := registry.Remove(oldSlug); err != nil {
		return err
	}
	if err := registry.Append(a); err != nil {
		return err
	}
	if a.Slug == oldSlug {
		fmt.Printf("Updated %s.\n", a.Label)
	}
	return nil
}

// setupToken runs `claude setup-token` (with competing auth scrubbed so it uses
// the browser, not an injected token) and reads back the pasted token.
func setupToken(in *bufio.Reader, label string) (string, error) {
	fmt.Fprintf(os.Stderr, "Generating a one-year OAuth token for %s.\n", label)
	fmt.Fprintln(os.Stderr, "The token is bound to whichever account is signed in on claude.ai in your browser.")
	fmt.Fprintln(os.Stderr, "Switch to the intended account on claude.ai first, then confirm it in the browser tab that opens.")

	cmd := exec.Command(claudeBin(), "setup-token")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = scrubbedEnv()
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("setup-token failed: %w", err)
	}

	token, err := promptLine(in, "Paste the generated token: ")
	if err != nil {
		return "", err
	}
	switch {
	case token == "":
		return "", errors.New("no token supplied; nothing was stored")
	case !strings.HasPrefix(token, "sk-ant-oat"):
		return "", errors.New("that does not look like a Claude OAuth token; nothing was stored")
	}
	return token, nil
}

func promptLine(in *bufio.Reader, label string) (string, error) {
	fmt.Fprint(os.Stderr, label)
	line, err := in.ReadString('\n')
	if err != nil && line == "" {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

func claudeBin() string {
	if p, err := exec.LookPath("claude"); err == nil {
		return p
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "bin", "claude")
}

func scrubbedEnv() []string {
	skip := map[string]bool{
		"CLAUDE_CODE_OAUTH_TOKEN": true,
		"ANTHROPIC_API_KEY":       true,
		"ANTHROPIC_AUTH_TOKEN":    true,
		"ANTHROPIC_BASE_URL":      true,
		"CLAUDE_CODE_USE_BEDROCK": true,
		"CLAUDE_CODE_USE_VERTEX":  true,
		"CLAUDE_CODE_USE_FOUNDRY": true,
	}
	var env []string
	for _, kv := range os.Environ() {
		if i := strings.IndexByte(kv, '='); i >= 0 && skip[kv[:i]] {
			continue
		}
		env = append(env, kv)
	}
	return env
}

func clearUsage(slug string) {
	_ = os.Remove(filepath.Join(paths.UsageDir(), slug+".json"))
}

// Slugify derives a command suffix from a display name: lowercase, spaces and
// punctuation collapsed to single hyphens, trimmed, with a leading claude-
// removed.
func Slugify(label string) string {
	s := strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			return r
		case r >= 'A' && r <= 'Z':
			return r + ('a' - 'A')
		case r == ' ', r == '-':
			return '-'
		default:
			return -1
		}
	}, label)
	for strings.Contains(s, "--") {
		s = strings.ReplaceAll(s, "--", "-")
	}
	return strings.TrimPrefix(strings.Trim(s, "-"), "claude-")
}
