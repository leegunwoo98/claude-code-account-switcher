#!/bin/zsh

emulate -L zsh
set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/claude-accounts-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

fail() {
  print -u2 -r -- "test failure: $*"
  exit 1
}

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/claude-subscriptions/usage"

export CLAUDE_SUBSCRIPTIONS_FILE="$XDG_CONFIG_HOME/claude-subscriptions/accounts.tsv"
export CLAUDE_SUBSCRIPTIONS_USAGE_DIR="$XDG_CONFIG_HOME/claude-subscriptions/usage"
export CLAUDE_SUBSCRIPTIONS_USAGE_SETTINGS="$XDG_CONFIG_HOME/claude-subscriptions/usage-settings.json"

print -r -- $'gmail\tGmail Work\tClaude Code Subscription: gmail' > "$CLAUDE_SUBSCRIPTIONS_FILE"
print -r -- '{"captured_at":1782540000,"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}' > "$CLAUDE_SUBSCRIPTIONS_USAGE_DIR/gmail.json"

source "$PROJECT_ROOT/src/claude-accounts.zsh"

typeset -f claude-accounts >/dev/null || fail "claude-accounts function was not loaded"
typeset -f claude-gmail >/dev/null || fail "claude-gmail function was not generated"

if typeset -f claude-claude-gmail >/dev/null; then
  print -u2 -r -- "unexpected duplicate claude- prefix"
  exit 1
fi

_claude_subscription_suggest_slug "claude-naver"
[[ "$REPLY" == "naver" ]] || fail "claude- prefix was not normalized"

_claude_subscription_usage_summary "gmail"
[[ "$REPLY" == "5h 24% · 7d 41% used" ]] || fail "usage summary was not formatted correctly"

print -r -- "runtime tests passed"
