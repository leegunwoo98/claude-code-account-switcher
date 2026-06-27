#!/bin/zsh

emulate -L zsh
set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/claude-accounts-install-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

fail() {
  print -u2 -r -- "test failure: $*"
  exit 1
}

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export CLAUDE_ACCOUNTS_INSTALL_ROOT="$HOME/.local/share/claude-code-account-switcher"
mkdir -p "$HOME/fake-bin"

print -r -- '#!/bin/sh' > "$HOME/fake-bin/claude"
print -r -- 'exit 0' >> "$HOME/fake-bin/claude"
chmod 700 "$HOME/fake-bin/claude"
export PATH="$HOME/fake-bin:$PATH"

zsh "$PROJECT_ROOT/install.zsh"

[[ -r "$CLAUDE_ACCOUNTS_INSTALL_ROOT/claude-accounts.zsh" ]] || fail "runtime was not installed"
[[ -x "$CLAUDE_ACCOUNTS_INSTALL_ROOT/capture-usage.zsh" ]] || fail "usage capture script is not executable"
[[ -x "$CLAUDE_ACCOUNTS_INSTALL_ROOT/uninstall.zsh" ]] || fail "uninstaller is not executable"
[[ -r "$XDG_CONFIG_HOME/claude-subscriptions/usage-settings.json" ]] || fail "usage settings were not installed"
grep -Fq '# >>> claude-code-account-switcher >>>' "$HOME/.zshrc" || fail "zshrc source block was not added"

zsh "$CLAUDE_ACCOUNTS_INSTALL_ROOT/uninstall.zsh"

[[ ! -e "$CLAUDE_ACCOUNTS_INSTALL_ROOT" ]] || fail "install root was not removed"
if grep -Fq '# >>> claude-code-account-switcher >>>' "$HOME/.zshrc"; then
  fail "zshrc source block was not removed"
fi
[[ -d "$XDG_CONFIG_HOME/claude-subscriptions" ]] || fail "configuration should be preserved by default"

print -r -- "installer tests passed"
