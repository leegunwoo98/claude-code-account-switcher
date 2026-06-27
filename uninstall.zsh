#!/bin/zsh

emulate -L zsh
set -euo pipefail

readonly INSTALL_ROOT="${CLAUDE_ACCOUNTS_INSTALL_ROOT:-$HOME/.local/share/claude-code-account-switcher}"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/claude-subscriptions"
readonly ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
readonly MARKER_START="# >>> claude-code-account-switcher >>>"
readonly MARKER_END="# <<< claude-code-account-switcher <<<"

if [[ -r "$INSTALL_ROOT/install.env" ]]; then
  source "$INSTALL_ROOT/install.env"
fi
readonly BIN_DIR="${CLAUDE_ACCOUNTS_BIN_DIR:-}"

purge=false
assume_yes=false

for argument in "$@"; do
  case "$argument" in
    --purge) purge=true ;;
    --yes) assume_yes=true ;;
    -h|--help)
      print -r -- "usage: uninstall.zsh [--purge] [--yes]"
      print -r -- "  --purge  also remove account metadata, usage cache, and Keychain tokens"
      print -r -- "  --yes    skip the purge confirmation"
      exit 0
      ;;
    *)
      print -u2 -r -- "unknown option: $argument"
      exit 2
      ;;
  esac
done

if [[ -f "$ZSHRC" ]] && grep -Fq "$MARKER_START" "$ZSHRC"; then
  temp_zshrc="$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")"
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$ZSHRC" > "$temp_zshrc"
  mv "$temp_zshrc" "$ZSHRC"
fi

registry="$CONFIG_ROOT/accounts.tsv"
if [[ -n "$BIN_DIR" && -r "$registry" ]]; then
  while IFS=$'\t' read -r slug label service extra; do
    link="$BIN_DIR/claude-${slug}"
    if [[ -L "$link" && "$(readlink "$link" 2>/dev/null || true)" == "claude-accounts" ]]; then
      rm -f "$link"
    fi
  done < "$registry"
fi
[[ -n "$BIN_DIR" ]] && rm -f "$BIN_DIR/claude-accounts"
rm -rf "$INSTALL_ROOT"

if $purge; then
  if ! $assume_yes; then
    read "answer?Delete all account metadata and Keychain tokens? [y/N] "
    [[ "$answer" == [yY] ]] || {
      print -r -- "Kept account metadata and Keychain tokens."
      print -r -- "Uninstalled shell integration."
      exit 0
    }
  fi

  if [[ -r "$registry" ]]; then
    while IFS=$'\t' read -r slug label service extra; do
      [[ -n "$service" ]] || continue
      /usr/bin/security delete-generic-password \
        -a "$USER" \
        -s "$service" >/dev/null 2>&1 || true
    done < "$registry"
  fi
  rm -rf "$CONFIG_ROOT"
  print -r -- "Removed account metadata, usage cache, and Keychain tokens."
else
  print -r -- "Account metadata and Keychain tokens were preserved."
fi

print -r -- "Uninstalled Claude Code Account Switcher."
