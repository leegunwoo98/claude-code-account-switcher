#!/bin/zsh

emulate -L zsh
set -euo pipefail

readonly PROJECT_ROOT="${0:A:h:h}"

zsh -n "$PROJECT_ROOT/src/claude-accounts.zsh"
zsh -n "$PROJECT_ROOT/src/capture-usage.zsh"
zsh -n "$PROJECT_ROOT/install.zsh"
zsh -n "$PROJECT_ROOT/uninstall.zsh"
jq empty "$PROJECT_ROOT/src/usage-settings.json"

zsh "$PROJECT_ROOT/tests/test.zsh"
zsh "$PROJECT_ROOT/tests/test-installer.zsh"
