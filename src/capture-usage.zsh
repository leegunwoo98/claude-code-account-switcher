#!/bin/zsh

set -u

slug="${CLAUDE_SUBSCRIPTION_SLUG:-}"
[[ -n "$slug" && "$slug" != -* && "$slug" != *- && "$slug" != *[^a-z0-9-]* ]] || exit 0
(( ${+commands[jq]} )) || exit 0

input="$(cat)"
rate_limits="$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)"
[[ -n "$rate_limits" ]] || exit 0

usage_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-subscriptions/usage"
mkdir -p "$usage_dir" || exit 0
chmod 700 "$usage_dir" 2>/dev/null

usage_file="$usage_dir/${slug}.json"
tmp_file="${usage_file}.tmp.$$"
captured_at="$(date +%s)"

printf '%s' "$input" | jq -c \
  --argjson captured_at "$captured_at" \
  '{captured_at: $captured_at, rate_limits: .rate_limits}' > "$tmp_file" 2>/dev/null || {
  rm -f "$tmp_file"
  exit 0
}

chmod 600 "$tmp_file" 2>/dev/null
mv "$tmp_file" "$usage_file"

# Intentionally print nothing: this status line exists only to cache usage.
exit 0
