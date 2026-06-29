// Package commands keeps the per-account claude-<slug> launchers in sync with
// the registry: each is a symlink to the main binary, which dispatches on its
// own name. Stale links for removed accounts are pruned.
package commands

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/leegunwoo98/claude-code-account-switcher/internal/registry"
)

func self() (dir, target string, ok bool) {
	exe, err := os.Executable()
	if err != nil {
		return "", "", false
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	return filepath.Dir(exe), filepath.Base(exe), true
}

// Sync ensures a claude-<slug> symlink exists for every account and removes our
// stale links. It only ever touches symlinks that point at the main binary, so
// it never clobbers an unrelated command of the same name.
func Sync(accounts []registry.Account) {
	dir, target, ok := self()
	if !ok {
		return
	}

	valid := map[string]bool{}
	for _, a := range accounts {
		valid[a.Command()] = true
		ensureLink(filepath.Join(dir, a.Command()), target)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, "claude-") || name == target || valid[name] {
			continue
		}
		if isOurLink(filepath.Join(dir, name), target) {
			_ = os.Remove(filepath.Join(dir, name))
		}
	}
}

func ensureLink(link, target string) {
	if fi, err := os.Lstat(link); err == nil {
		// Already present: leave it unless it's our link to a different target.
		if fi.Mode()&os.ModeSymlink != 0 {
			if t, _ := os.Readlink(link); t == target {
				return
			}
		}
		return
	}
	_ = os.Symlink(target, link)
}

func isOurLink(link, target string) bool {
	fi, err := os.Lstat(link)
	if err != nil || fi.Mode()&os.ModeSymlink == 0 {
		return false
	}
	t, _ := os.Readlink(link)
	return t == target
}
