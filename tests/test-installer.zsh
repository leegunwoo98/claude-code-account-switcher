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
mkdir -p "$XDG_CONFIG_HOME/claude-subscriptions"
print -r -- $'gmail\tGmail Work\tClaude Code Subscription: gmail' > "$XDG_CONFIG_HOME/claude-subscriptions/accounts.tsv"

print -r -- '#!/bin/sh' > "$HOME/fake-bin/claude"
print -r -- 'exit 0' >> "$HOME/fake-bin/claude"
chmod 700 "$HOME/fake-bin/claude"
export PATH="$HOME/fake-bin:$PATH"
readonly EXPECTED_BIN_DIR="$HOME/fake-bin"

zsh "$PROJECT_ROOT/install.zsh"

[[ -r "$CLAUDE_ACCOUNTS_INSTALL_ROOT/claude-accounts.zsh" ]] || fail "runtime was not installed"
[[ -x "$CLAUDE_ACCOUNTS_INSTALL_ROOT/capture-usage.zsh" ]] || fail "usage capture script is not executable"
[[ -x "$CLAUDE_ACCOUNTS_INSTALL_ROOT/uninstall.zsh" ]] || fail "uninstaller is not executable"
[[ -x "$EXPECTED_BIN_DIR/claude-accounts" ]] || fail "claude-accounts executable was not installed"
[[ -L "$EXPECTED_BIN_DIR/claude-gmail" ]] || fail "claude-gmail executable was not generated"
[[ -r "$XDG_CONFIG_HOME/claude-subscriptions/usage-settings.json" ]] || fail "usage settings were not installed"
[[ ! -e "$HOME/.zshrc" ]] || fail "installer should not create or modify zshrc"

PATH="$EXPECTED_BIN_DIR:$PATH" /bin/bash -c 'claude-accounts --help' >/dev/null || \
  fail "claude-accounts was not callable from Bash"

zsh "$CLAUDE_ACCOUNTS_INSTALL_ROOT/uninstall.zsh"

[[ ! -e "$CLAUDE_ACCOUNTS_INSTALL_ROOT" ]] || fail "install root was not removed"
[[ ! -e "$EXPECTED_BIN_DIR/claude-accounts" ]] || fail "claude-accounts executable was not removed"
[[ ! -e "$EXPECTED_BIN_DIR/claude-gmail" ]] || fail "claude-gmail executable was not removed"
[[ -d "$XDG_CONFIG_HOME/claude-subscriptions" ]] || fail "configuration should be preserved by default"

print -r -- "installer tests passed"
