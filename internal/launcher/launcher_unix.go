//go:build !windows

package launcher

import "syscall"

// execClaude replaces the current process with claude so it owns the terminal
// and signals directly.
func execClaude(bin string, argv, env []string) error {
	return syscall.Exec(bin, argv, env)
}
