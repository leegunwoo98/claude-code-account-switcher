//go:build darwin

package credstore

import (
	"errors"
	"os"
	"os/exec"
	"strings"
)

// Get reads the token stored in the login Keychain under the given service
// name. A missing item (security exit code 44, errSecItemNotFound) is reported
// as an empty token, not an error.
func Get(service string) (string, error) {
	cmd := exec.Command("/usr/bin/security", "find-generic-password",
		"-a", os.Getenv("USER"), "-s", service, "-w")
	out, err := cmd.Output()
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			// 44 == errSecItemNotFound: no token configured for this service.
			return "", nil
		}
		return "", err
	}
	return strings.TrimRight(string(out), "\r\n"), nil
}

// Set stores or replaces (-U) the token under the service name.
func Set(service, token string) error {
	return exec.Command("/usr/bin/security", "add-generic-password",
		"-U", "-a", os.Getenv("USER"), "-s", service, "-l", service, "-w", token).Run()
}

// Delete removes the token for a service. A missing item is not an error.
func Delete(service string) error {
	err := exec.Command("/usr/bin/security", "delete-generic-password",
		"-a", os.Getenv("USER"), "-s", service).Run()
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return nil
	}
	return err
}
