// Package manager is the interactive claude-accounts UI: choose an account, then
// Launch / Edit / Refresh / Remove — or Add a new one. It mirrors the zsh menu.
package manager

import (
	"fmt"
	"os"

	"github.com/leegunwoo98/claude-code-account-switcher/internal/commands"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/credstore"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/launcher"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/manage"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/menu"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/registry"
	"github.com/leegunwoo98/claude-code-account-switcher/internal/usage"
)

// Run loops the account picker until the user launches a session or cancels.
func Run() error {
	for {
		accounts, err := registry.Load()
		if err != nil {
			return err
		}
		commands.Sync(accounts)

		labels := []string{"+ Add subscription"}
		for _, a := range accounts {
			state := "token missing"
			if t, _ := credstore.Get(a.Service); t != "" {
				state = "configured"
			}
			labels = append(labels, fmt.Sprintf("%s  [%s]  (%s; %s)", a.Label, a.Command(), state, usage.Summary(a.Slug)))
		}

		idx, ok := menu.Select("Claude accounts > ", "Select an account to manage or launch", labels)
		if !ok {
			return nil
		}
		if idx == 0 {
			report(manage.Add())
			continue
		}

		acct := accounts[idx-1]
		actions := []string{"Launch", "Edit", "Refresh token", "Remove", "Back"}
		aidx, ok := menu.Select(acct.Label+" > ", "Choose an action", actions)
		if !ok {
			continue
		}
		switch aidx {
		case 0:
			return launcher.Launch(acct, nil) // replaces the process on success
		case 1:
			report(manage.Edit(acct.Slug))
		case 2:
			report(manage.Refresh(acct.Slug))
		case 3:
			report(manage.Remove(acct.Slug))
		}
	}
}

func report(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
	}
}
