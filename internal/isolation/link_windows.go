//go:build windows

package isolation

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
)

var (
	probeOnce sync.Once
	symlinkOK bool
)

// symlinkCapable probes once whether unprivileged symlink creation works
// (requires Windows Developer Mode). Probing once avoids a failed syscall per
// entry in the hot path.
func symlinkCapable() bool {
	probeOnce.Do(func() {
		tmp, err := os.MkdirTemp("", "cc-link-probe")
		if err != nil {
			return
		}
		defer os.RemoveAll(tmp)
		target := filepath.Join(tmp, "t")
		if os.Mkdir(target, 0o700) != nil {
			return
		}
		symlinkOK = os.Symlink(target, filepath.Join(tmp, "l")) == nil
	})
	return symlinkOK
}

// linkEntry shares a base entry into the account dir without requiring admin:
// symlink (Developer Mode) → directory junction / file hardlink → copy. Junction
// and hardlink need no privilege; copy is the last resort and does not stay in
// sync with later edits.
func linkEntry(target, link string, isDir bool) error {
	if symlinkCapable() {
		if err := os.Symlink(target, link); err == nil {
			return nil
		}
	}
	if isDir {
		if err := exec.Command("cmd", "/c", "mklink", "/J", link, target).Run(); err == nil {
			return nil
		}
		return copyTree(target, link)
	}
	if err := os.Link(target, link); err == nil {
		return nil
	}
	return copyFile(target, link)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func copyTree(src, dst string) error {
	return filepath.WalkDir(src, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, p)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o700)
		}
		return copyFile(p, target)
	})
}
