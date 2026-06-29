// Package isolation builds a per-account CLAUDE_CONFIG_DIR that shares every
// part of the base Claude config except the cached account identity.
//
// Claude Code pins the account/organization cached in .claude.json's
// "oauthAccount" onto every request, so injecting a different account's token
// alone still bills the signed-in plan. We give each account its own config dir
// that symlinks everything from the base config (settings, plugins, memory,
// history) but writes its own .claude.json with only "oauthAccount" removed.
package isolation

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"github.com/leegunwoo98/claude-code-account-switcher/internal/paths"
)

// Build creates or refreshes the per-account config dir and returns its path.
func Build(slug string) (string, error) {
	base := paths.ClaudeHome()
	acctDir := filepath.Join(paths.ConfigsDir(), slug)

	if err := os.MkdirAll(acctDir, 0o700); err != nil {
		return "", err
	}

	if err := mirror(base, acctDir); err != nil {
		return "", err
	}
	if err := writeStripped(paths.ClaudeJSON(), filepath.Join(acctDir, ".claude.json")); err != nil {
		return "", err
	}
	return acctDir, nil
}

// mirror symlinks every entry of base into acctDir (share-by-default), except
// the account file (regenerated separately) and per-process runtime that must
// stay isolated. Stale links whose source disappeared are pruned.
func mirror(base, acctDir string) error {
	want := map[string]bool{}
	if entries, err := os.ReadDir(base); err == nil {
		for _, e := range entries {
			name := e.Name()
			if name == ".claude.json" || isolatedName(name) {
				continue
			}
			want[name] = true
			link := filepath.Join(acctDir, name)
			_ = os.Remove(link)
			if err := linkEntry(filepath.Join(base, name), link, e.IsDir()); err != nil {
				return err
			}
		}
	}

	// Prune our stale symlinks; never touch real files Claude created here.
	if entries, err := os.ReadDir(acctDir); err == nil {
		for _, e := range entries {
			name := e.Name()
			if name == ".claude.json" || want[name] {
				continue
			}
			full := filepath.Join(acctDir, name)
			if info, err := os.Lstat(full); err == nil && info.Mode()&os.ModeSymlink != 0 {
				_ = os.Remove(full)
			}
		}
	}
	return nil
}

func isolatedName(name string) bool {
	switch {
	case name == "daemon", strings.HasPrefix(name, "daemon."):
		return true
	case strings.HasSuffix(name, ".lock"), strings.HasSuffix(name, ".sock"):
		return true
	}
	return false
}

// writeStripped copies the base .claude.json to dst with the top-level
// "oauthAccount" key removed. Decoding into json.RawMessage preserves every
// other value's exact bytes (floats, nulls, nested structure), so the only
// change is the dropped account and re-sorted top-level keys.
func writeStripped(src, dst string) error {
	b, err := os.ReadFile(src)
	if err != nil {
		if os.IsNotExist(err) {
			// Never logged in: nothing to strip, no account to leak.
			return os.WriteFile(dst, []byte("{}\n"), 0o600)
		}
		return err
	}

	var top map[string]json.RawMessage
	if err := json.Unmarshal(b, &top); err != nil {
		return err
	}
	delete(top, "oauthAccount")

	out, err := json.Marshal(top)
	if err != nil {
		return err
	}

	tmp := dst + ".tmp"
	if err := os.WriteFile(tmp, out, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, dst)
}
