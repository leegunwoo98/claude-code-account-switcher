//go:build !windows

package isolation

import "os"

// linkEntry shares a base entry into the account dir. On Unix a plain symlink
// needs no privilege and works for both files and directories.
func linkEntry(target, link string, isDir bool) error {
	return os.Symlink(target, link)
}
