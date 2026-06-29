// Package menu presents an interactive chooser, using fzf when available (to
// match the zsh UI) and falling back to a numbered prompt otherwise.
package menu

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// Select shows labels under a prompt/header and returns the chosen index, or
// ok=false when the user cancels.
func Select(prompt, header string, labels []string) (int, bool) {
	if len(labels) == 0 {
		return 0, false
	}
	if fzf, err := exec.LookPath("fzf"); err == nil {
		return fzfSelect(fzf, prompt, header, labels)
	}
	return numberedSelect(prompt, header, labels)
}

func fzfSelect(fzf, prompt, header string, labels []string) (int, bool) {
	var in bytes.Buffer
	for i, l := range labels {
		fmt.Fprintf(&in, "%d\t%s\n", i, l)
	}
	cmd := exec.Command(fzf,
		"--prompt="+prompt,
		"--header="+header,
		"--height=40%", "--layout=reverse", "--border", "--no-multi",
		"--delimiter=\t", "--with-nth=2..",
	)
	cmd.Stdin = &in
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return 0, false
	}
	field := strings.SplitN(strings.TrimRight(string(out), "\n"), "\t", 2)
	idx, err := strconv.Atoi(field[0])
	if err != nil || idx < 0 || idx >= len(labels) {
		return 0, false
	}
	return idx, true
}

func numberedSelect(prompt, header string, labels []string) (int, bool) {
	if header != "" {
		fmt.Fprintln(os.Stderr, header)
	}
	for i, l := range labels {
		fmt.Fprintf(os.Stderr, "  %d) %s\n", i+1, l)
	}
	fmt.Fprintf(os.Stderr, "  0) Cancel\n%s", prompt)

	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(line))
	if err != nil || n <= 0 || n > len(labels) {
		return 0, false
	}
	return n - 1, true
}
