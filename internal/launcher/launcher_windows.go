//go:build windows

package launcher

import (
	"errors"
	"os"
	"os/exec"
)

// execClaude runs claude as a child with inherited stdio and propagates its
// exit code. Windows has no process-replacement equivalent of syscall.Exec, and
// the child shares the console so it receives Ctrl-C directly.
func execClaude(bin string, argv, env []string) error {
	cmd := exec.Command(bin, argv[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = env
	err := cmd.Run()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		os.Exit(ee.ExitCode())
	}
	return err
}
