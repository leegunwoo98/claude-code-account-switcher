//go:build !darwin

package credstore

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	"github.com/leegunwoo98/claude-code-account-switcher/internal/paths"
)

// On Linux and Windows, tokens live in a 0600 JSON file under the config dir —
// the same model Claude Code uses for its own .credentials.json. This works
// headless (servers, CI, containers), unlike an OS keyring that needs a running
// Secret Service / D-Bus session.
var fileMu sync.Mutex

func tokensFile() string {
	return filepath.Join(paths.ConfigRoot(), "tokens.json")
}

func readAll() (map[string]string, error) {
	b, err := os.ReadFile(tokensFile())
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]string{}, nil
		}
		return nil, err
	}
	m := map[string]string{}
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	return m, nil
}

func writeAll(m map[string]string) error {
	if err := os.MkdirAll(paths.ConfigRoot(), 0o700); err != nil {
		return err
	}
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	tmp := tokensFile() + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, tokensFile())
}

// Get returns the token for a service, or "" when absent.
func Get(service string) (string, error) {
	fileMu.Lock()
	defer fileMu.Unlock()
	m, err := readAll()
	if err != nil {
		return "", err
	}
	return m[service], nil
}

// Set stores or replaces the token for a service.
func Set(service, token string) error {
	fileMu.Lock()
	defer fileMu.Unlock()
	m, err := readAll()
	if err != nil {
		return err
	}
	m[service] = token
	return writeAll(m)
}

// Delete removes the token for a service. Absent is not an error.
func Delete(service string) error {
	fileMu.Lock()
	defer fileMu.Unlock()
	m, err := readAll()
	if err != nil {
		return err
	}
	delete(m, service)
	return writeAll(m)
}
