#!/bin/zsh

emulate -L zsh
set -euo pipefail

readonly REPOSITORY="leegunwoo98/claude-code-account-switcher"
readonly VERSION="${CLAUDE_ACCOUNTS_VERSION:-main}"
readonly INSTALL_ROOT="${CLAUDE_ACCOUNTS_INSTALL_ROOT:-$HOME/.local/share/claude-code-account-switcher}"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/claude-subscriptions"
readonly ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
readonly MARKER_START="# >>> claude-code-account-switcher >>>"
readonly MARKER_END="# <<< claude-code-account-switcher <<<"
readonly SCRIPT_DIR="${0:A:h}"

typeset temp_dir=""

cleanup() {
  [[ -n "$temp_dir" && -d "$temp_dir" ]] && rm -rf "$temp_dir"
}
trap cleanup EXIT INT TERM

fail() {
  print -u2 -r -- "error: $*"
  exit 1
}

for dependency in zsh curl install; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command not found: $dependency"
done

[[ "$OSTYPE" == darwin* ]] || fail "only macOS is currently supported because credentials use macOS Keychain"
command -v security >/dev/null 2>&1 || fail "macOS security command not found"
command -v claude >/dev/null 2>&1 || fail "Claude Code is not installed or not on PATH"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/claude-accounts.XXXXXX")"

fetch_file() {
  local relative_path="$1"
  local destination="$2"

  if [[ -f "$SCRIPT_DIR/$relative_path" ]]; then
    cp "$SCRIPT_DIR/$relative_path" "$destination"
  else
    curl -fsSL \
      "https://raw.githubusercontent.com/$REPOSITORY/$VERSION/$relative_path" \
      -o "$destination"
  fi
}

fetch_file "src/claude-accounts.zsh" "$temp_dir/claude-accounts.zsh"
fetch_file "src/capture-usage.zsh" "$temp_dir/capture-usage.zsh"
fetch_file "src/usage-settings.json" "$temp_dir/usage-settings.json"
fetch_file "uninstall.zsh" "$temp_dir/uninstall.zsh"

install -d -m 700 "$INSTALL_ROOT" "$CONFIG_ROOT"
install -m 600 "$temp_dir/claude-accounts.zsh" "$INSTALL_ROOT/claude-accounts.zsh"
install -m 700 "$temp_dir/capture-usage.zsh" "$INSTALL_ROOT/capture-usage.zsh"
install -m 700 "$temp_dir/uninstall.zsh" "$INSTALL_ROOT/uninstall.zsh"

sed "s|\$HOME/.local/share/claude-code-account-switcher|$INSTALL_ROOT|g" \
  "$temp_dir/usage-settings.json" > "$temp_dir/usage-settings.resolved.json"
install -m 600 "$temp_dir/usage-settings.resolved.json" "$CONFIG_ROOT/usage-settings.json"

mkdir -p "${ZSHRC:h}"
touch "$ZSHRC"

if ! grep -Fq "$MARKER_START" "$ZSHRC"; then
  {
    print
    print -r -- "$MARKER_START"
    print -r -- "source \"$INSTALL_ROOT/claude-accounts.zsh\""
    print -r -- "$MARKER_END"
  } >> "$ZSHRC"
fi

print -r -- "Installed Claude Code Account Switcher."
print -r -- "Start a new shell or run:"
print -r -- "  source \"$INSTALL_ROOT/claude-accounts.zsh\""
print -r -- "Then open the UI with:"
print -r -- "  claude-accounts"

if ! command -v fzf >/dev/null 2>&1; then
  print -r -- "Optional: install fzf for the interactive selector."
fi
if ! command -v jq >/dev/null 2>&1; then
  print -r -- "Optional: install jq to display cached rate-limit usage."
fi
