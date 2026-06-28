# Claude Code subscription selector.
# Tokens live in macOS Keychain; account metadata lives in accounts.tsv.
# Claude settings and session history remain shared in ~/.claude.

typeset -g CLAUDE_SUBSCRIPTIONS_DIR="${CLAUDE_SUBSCRIPTIONS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-subscriptions}"
typeset -g CLAUDE_SUBSCRIPTIONS_FILE="${CLAUDE_SUBSCRIPTIONS_FILE:-$CLAUDE_SUBSCRIPTIONS_DIR/accounts.tsv}"
typeset -g CLAUDE_SUBSCRIPTIONS_USAGE_DIR="${CLAUDE_SUBSCRIPTIONS_USAGE_DIR:-$CLAUDE_SUBSCRIPTIONS_DIR/usage}"
typeset -g CLAUDE_SUBSCRIPTIONS_USAGE_SETTINGS="${CLAUDE_SUBSCRIPTIONS_USAGE_SETTINGS:-$CLAUDE_SUBSCRIPTIONS_DIR/usage-settings.json}"
typeset -g CLAUDE_ACCOUNTS_BIN_DIR="${CLAUDE_ACCOUNTS_BIN_DIR:-}"

if (( ${+_CLAUDE_SUBSCRIPTION_GENERATED_COMMANDS} )); then
  for _claude_stale_command in "${_CLAUDE_SUBSCRIPTION_GENERATED_COMMANDS[@]}"; do
    unfunction "$_claude_stale_command" 2>/dev/null
  done
  unset _claude_stale_command
fi

typeset -ga _CLAUDE_SUBSCRIPTION_SLUGS=()
typeset -gA _CLAUDE_SUBSCRIPTION_LABELS=()
typeset -gA _CLAUDE_SUBSCRIPTION_SERVICES=()
typeset -ga _CLAUDE_SUBSCRIPTION_GENERATED_COMMANDS=()

_claude_subscription_validate_slug() {
  local slug="$1"
  [[ -n "$slug" && "$slug" != -* && "$slug" != *- && "$slug" != *[^a-z0-9-]* ]]
}

_claude_subscription_validate_label() {
  local label="$1"
  [[ -n "$label" && "$label" != *$'\t'* && "$label" != *$'\n'* ]]
}

_claude_subscription_service_for_slug() {
  REPLY="Claude Code Subscription: $1"
}

_claude_subscription_is_configured() {
  local service="$1"
  /usr/bin/security find-generic-password \
    -a "$USER" \
    -s "$service" >/dev/null 2>&1
}

_claude_subscription_usage_summary() {
  local slug="$1"
  local usage_file="$CLAUDE_SUBSCRIPTIONS_USAGE_DIR/${slug}.json"
  local five_hour seven_day

  if [[ ! -r "$usage_file" ]] || (( ! ${+commands[jq]} )); then
    REPLY="usage pending"
    return 0
  fi

  five_hour="$(jq -r '.rate_limits.five_hour.used_percentage // empty' "$usage_file" 2>/dev/null)"
  seven_day="$(jq -r '.rate_limits.seven_day.used_percentage // empty' "$usage_file" 2>/dev/null)"

  if [[ -z "$five_hour" && -z "$seven_day" ]]; then
    REPLY="usage pending"
    return 0
  fi

  REPLY=""
  [[ -n "$five_hour" ]] && REPLY="5h $(printf '%.0f' "$five_hour")%"
  [[ -n "$seven_day" ]] && REPLY="${REPLY:+$REPLY · }7d $(printf '%.0f' "$seven_day")%"
  REPLY="$REPLY used"
}

_claude_subscription_has_explicit_session_name() {
  local argument

  for argument in "$@"; do
    [[ "$argument" == "--" ]] && return 1
    case "$argument" in
      --name|--name=*|-n|-n?*) return 0 ;;
    esac
  done

  return 1
}

_claude_subscription_register_command() {
  local slug="$1"
  local command_name="claude-${slug}"
  local command_path="${commands[$command_name]-}"
  local managed_path="${CLAUDE_ACCOUNTS_BIN_DIR:+$CLAUDE_ACCOUNTS_BIN_DIR/$command_name}"

  _claude_subscription_sync_executable "$slug"
  [[ "${CLAUDE_ACCOUNTS_STANDALONE:-0}" == "1" ]] && return 0

  command_path="${commands[$command_name]-}"
  if (( ${+functions[$command_name]} || ${+aliases[$command_name]} )) || \
    [[ -n "$command_path" && "$command_path" != "$managed_path" ]]; then
    print -u2 -r -- "Skipping generated command ${command_name}: that name is already in use."
    return 0
  fi

  eval "${command_name}() { _claude_subscription_run ${(q)slug} \"\$@\"; }"
  _CLAUDE_SUBSCRIPTION_GENERATED_COMMANDS+=("$command_name")
}

_claude_subscription_sync_executable() {
  local slug="$1"
  local launcher link target

  [[ -n "$CLAUDE_ACCOUNTS_BIN_DIR" ]] || return 0
  launcher="$CLAUDE_ACCOUNTS_BIN_DIR/claude-accounts"
  link="$CLAUDE_ACCOUNTS_BIN_DIR/claude-${slug}"
  [[ -x "$launcher" ]] || return 0

  if [[ -L "$link" ]]; then
    target="$(readlink "$link" 2>/dev/null || true)"
    [[ "$target" == "claude-accounts" ]] && return 0
  fi
  if [[ -e "$link" || -L "$link" ]]; then
    print -u2 -r -- "Skipping executable ${link}: that path is already in use."
    return 1
  fi

  ln -s "claude-accounts" "$link"
}

_claude_subscription_remove_executable() {
  local slug="$1"
  local link target

  [[ -n "$CLAUDE_ACCOUNTS_BIN_DIR" ]] || return 0
  link="$CLAUDE_ACCOUNTS_BIN_DIR/claude-${slug}"
  [[ -L "$link" ]] || return 0
  target="$(readlink "$link" 2>/dev/null || true)"
  [[ "$target" == "claude-accounts" ]] && rm -f "$link"
}

_claude_subscriptions_reload() {
  local command_name slug label service extra

  for command_name in "${_CLAUDE_SUBSCRIPTION_GENERATED_COMMANDS[@]}"; do
    unfunction "$command_name" 2>/dev/null
  done

  _CLAUDE_SUBSCRIPTION_SLUGS=()
  _CLAUDE_SUBSCRIPTION_LABELS=()
  _CLAUDE_SUBSCRIPTION_SERVICES=()
  _CLAUDE_SUBSCRIPTION_GENERATED_COMMANDS=()

  [[ -r "$CLAUDE_SUBSCRIPTIONS_FILE" ]] || return 0

  while IFS=$'\t' read -r slug label service extra; do
    [[ -z "$slug" || "$slug" == \#* ]] && continue

    if ! _claude_subscription_validate_slug "$slug"; then
      print -u2 -r -- "Ignoring invalid Claude subscription command suffix: ${slug}"
      continue
    fi
    if ! _claude_subscription_validate_label "$label"; then
      print -u2 -r -- "Ignoring Claude subscription ${slug}: invalid display name."
      continue
    fi
    if [[ -z "$service" || "$service" == *$'\t'* || "$service" == *$'\n'* ]]; then
      print -u2 -r -- "Ignoring Claude subscription ${slug}: invalid Keychain service."
      continue
    fi
    if [[ -n "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
      print -u2 -r -- "Ignoring duplicate Claude subscription command suffix: ${slug}"
      continue
    fi

    _CLAUDE_SUBSCRIPTION_SLUGS+=("$slug")
    _CLAUDE_SUBSCRIPTION_LABELS[$slug]="$label"
    _CLAUDE_SUBSCRIPTION_SERVICES[$slug]="$service"
    _claude_subscription_register_command "$slug"
  done < "$CLAUDE_SUBSCRIPTIONS_FILE"
}

_claude_subscription_pick() {
  local slug label service state selected item
  local -a choices=()
  local -a fallback_choices=()

  if (( ${#_CLAUDE_SUBSCRIPTION_SLUGS[@]} == 0 )); then
    print -u2 -r -- "No Claude subscriptions configured."
    print -u2 -r -- "Run: claude-accounts"
    return 1
  fi

  for slug in "${_CLAUDE_SUBSCRIPTION_SLUGS[@]}"; do
    label="${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}"
    service="${_CLAUDE_SUBSCRIPTION_SERVICES[$slug]}"
    if _claude_subscription_is_configured "$service"; then
      state="configured"
    else
      state="token missing"
    fi
    choices+=("${slug}\t${label}\t${state}\tclaude-${slug}")
    fallback_choices+=("${label} [claude-${slug}] (${state})")
  done

  if (( ${+commands[fzf]} )); then
    selected="$(printf '%b\n' "${choices[@]}" | fzf \
      --prompt='Claude subscription > ' \
      --height=40% \
      --layout=reverse \
      --border \
      --no-multi \
      --with-nth=2..)" || return 1
    REPLY="${selected%%$'\t'*}"
    return 0
  fi

  print -r -- "Select Claude subscription:"
  select item in "${fallback_choices[@]}" "Cancel"; do
    if (( REPLY == ${#fallback_choices[@]} + 1 )); then
      return 1
    fi
    if (( REPLY >= 1 && REPLY <= ${#fallback_choices[@]} )); then
      REPLY="${_CLAUDE_SUBSCRIPTION_SLUGS[$REPLY]}"
      return 0
    fi
    print -u2 -r -- "Invalid selection."
  done
}

_claude_with_subscription() {
  local label="$1"
  local service="$2"
  local slug="$3"
  shift 3

  local token claude_bin exit_code
  local -a usage_settings_args=()
  local -a session_name_args=()
  claude_bin="${commands[claude]:-$HOME/.local/bin/claude}"
  [[ -r "$CLAUDE_SUBSCRIPTIONS_USAGE_SETTINGS" ]] && usage_settings_args=(--settings "$CLAUDE_SUBSCRIPTIONS_USAGE_SETTINGS")
  if ! _claude_subscription_has_explicit_session_name "$@"; then
    session_name_args=(--name "$label")
  fi

  token="$(/usr/bin/security find-generic-password \
    -a "$USER" \
    -s "$service" \
    -w 2>/dev/null)" || {
      print -u2 -r -- "No Keychain token found for ${label}."
      print -u2 -r -- "Run: claude-accounts"
      return 1
    }

  print -u2 -r -- "Starting Claude with subscription: ${label}"

  /usr/bin/env \
    -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_AUTH_TOKEN \
    -u ANTHROPIC_BASE_URL \
    -u CLAUDE_CODE_USE_BEDROCK \
    -u CLAUDE_CODE_USE_VERTEX \
    -u CLAUDE_CODE_USE_FOUNDRY \
    CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 \
    CLAUDE_CODE_OAUTH_TOKEN="$token" \
    CLAUDE_SUBSCRIPTION_SLUG="$slug" \
    "$claude_bin" "${usage_settings_args[@]}" "${session_name_args[@]}" "$@"
  exit_code=$?

  token=""
  unset token
  return "$exit_code"
}

_claude_subscription_run() {
  local slug="$1"
  shift

  if [[ -z "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
    print -u2 -r -- "Unknown Claude subscription: ${slug}"
    print -u2 -r -- "Run: claude-accounts"
    return 1
  fi

  _claude_with_subscription \
    "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}" \
    "${_CLAUDE_SUBSCRIPTION_SERVICES[$slug]}" \
    "$slug" \
    "$@"
}

_claude_subscription_suggest_slug() {
  local label="$1"
  local slug="${(L)label}"
  slug="${slug// /-}"
  slug="${slug//[^a-z0-9-]/}"
  while [[ "$slug" == *--* ]]; do
    slug="${slug//--/-}"
  done
  slug="${slug#-}"
  slug="${slug%-}"
  slug="${slug#claude-}"
  REPLY="$slug"
}

_claude_subscription_new_identity() {
  local preferred_slug="${1:-}"
  local label slug suggested command_name

  read "label?Subscription display name: "
  if ! _claude_subscription_validate_label "$label"; then
    print -u2 -r -- "Display name must be non-empty and cannot contain tabs or newlines."
    return 1
  fi

  _claude_subscription_suggest_slug "$label"
  suggested="$REPLY"
  [[ -n "$preferred_slug" ]] && suggested="$preferred_slug"
  read "slug?Direct command suffix, without claude- [${suggested}]: "
  slug="${slug:-$suggested}"
  slug="${slug#claude-}"

  if ! _claude_subscription_validate_slug "$slug"; then
    print -u2 -r -- "Command suffix must use lowercase letters, numbers, and internal hyphens only."
    return 1
  fi
  if [[ -n "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
    print -u2 -r -- "Subscription command suffix already exists: ${slug}"
    return 1
  fi

  command_name="claude-${slug}"
  if (( ${+functions[$command_name]} || ${+aliases[$command_name]} || ${+commands[$command_name]} )); then
    print -u2 -r -- "Command name is already in use: ${command_name}"
    return 1
  fi

  REPLY="${slug}"$'\t'"${label}"
}

_claude_subscription_save_new() {
  local slug="$1"
  local label="$2"
  local service="$3"

  mkdir -p "$CLAUDE_SUBSCRIPTIONS_DIR" || return 1
  chmod 700 "$CLAUDE_SUBSCRIPTIONS_DIR" 2>/dev/null
  printf '%s\t%s\t%s\n' "$slug" "$label" "$service" >> "$CLAUDE_SUBSCRIPTIONS_FILE" || return 1
  chmod 600 "$CLAUDE_SUBSCRIPTIONS_FILE" 2>/dev/null
}

_claude_subscription_add() {
  local slug="${1:-}"
  local label service token claude_bin exit_code identity

  if [[ -n "$slug" && -n "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
    label="${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}"
    service="${_CLAUDE_SUBSCRIPTION_SERVICES[$slug]}"
  else
    if [[ -n "$slug" ]]; then
      print -u2 -r -- "Unknown subscription suffix: ${slug}; creating a new subscription."
    fi
    _claude_subscription_new_identity "$slug" || return 1
    identity="$REPLY"
    slug="${identity%%$'\t'*}"
    label="${identity#*$'\t'}"
    _claude_subscription_service_for_slug "$slug"
    service="$REPLY"
  fi

  claude_bin="${commands[claude]:-$HOME/.local/bin/claude}"
  print -r -- "Generating a one-year OAuth token for ${label}."
  print -r -- "Confirm the intended Claude account in the browser, then copy the generated token."

  /usr/bin/env \
    -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_AUTH_TOKEN \
    -u ANTHROPIC_BASE_URL \
    -u CLAUDE_CODE_OAUTH_TOKEN \
    -u CLAUDE_CODE_USE_BEDROCK \
    -u CLAUDE_CODE_USE_VERTEX \
    -u CLAUDE_CODE_USE_FOUNDRY \
    "$claude_bin" setup-token || return 1

  read -rs "token?Paste the generated token for ${label}: "
  print
  if [[ -z "$token" ]]; then
    print -u2 -r -- "No token supplied; Keychain was not changed."
    return 1
  fi
  if [[ "$token" != sk-ant-oat* ]]; then
    print -u2 -r -- "The pasted value does not look like a Claude OAuth token; Keychain was not changed."
    token=""
    unset token
    return 1
  fi

  /usr/bin/security add-generic-password \
    -U \
    -a "$USER" \
    -s "$service" \
    -l "$service" \
    -w "$token"
  exit_code=$?
  (( exit_code == 0 )) || {
    token=""
    unset token
    return "$exit_code"
  }

  token=""
  unset token

  if [[ -z "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
    _claude_subscription_save_new "$slug" "$label" "$service" || return 1
    _claude_subscriptions_reload
  fi

  print -r -- "Stored ${label} token in macOS Keychain."
  print -r -- "Remote validity will be checked when this subscription is first used."
  print -r -- "Direct command: claude-${slug}"
}

_claude_subscription_remove() {
  local slug="${1:-}"
  local label service answer tmp current_slug current_label current_service extra

  if [[ -z "$slug" ]]; then
    _claude_subscription_pick || return 1
    slug="$REPLY"
  fi
  if [[ -z "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
    print -u2 -r -- "Unknown Claude subscription: ${slug}"
    return 1
  fi

  label="${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}"
  service="${_CLAUDE_SUBSCRIPTION_SERVICES[$slug]}"
  read "answer?Remove ${label} and its Keychain token? [y/N] "
  [[ "$answer" == [yY] ]] || return 1

  /usr/bin/security delete-generic-password -a "$USER" -s "$service" >/dev/null 2>&1
  _claude_subscription_remove_executable "$slug"

  tmp="${CLAUDE_SUBSCRIPTIONS_FILE}.tmp.$$"
  : > "$tmp" || return 1
  while IFS=$'\t' read -r current_slug current_label current_service extra; do
    [[ "$current_slug" == "$slug" ]] && continue
    printf '%s\t%s\t%s\n' "$current_slug" "$current_label" "$current_service" >> "$tmp"
  done < "$CLAUDE_SUBSCRIPTIONS_FILE"
  mv "$tmp" "$CLAUDE_SUBSCRIPTIONS_FILE" || return 1
  chmod 600 "$CLAUDE_SUBSCRIPTIONS_FILE" 2>/dev/null

  _claude_subscriptions_reload
  print -r -- "Removed ${label}."
}

_claude_subscription_edit() {
  local slug="$1"
  local old_label service new_label new_slug command_name tmp
  local current_slug current_label current_service extra

  if [[ -z "${_CLAUDE_SUBSCRIPTION_LABELS[$slug]-}" ]]; then
    print -u2 -r -- "Unknown Claude subscription: ${slug}"
    return 1
  fi

  old_label="${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}"
  service="${_CLAUDE_SUBSCRIPTION_SERVICES[$slug]}"

  read "new_label?Display name [${old_label}]: "
  new_label="${new_label:-$old_label}"
  if ! _claude_subscription_validate_label "$new_label"; then
    print -u2 -r -- "Display name must be non-empty and cannot contain tabs or newlines."
    return 1
  fi

  read "new_slug?Direct command suffix [${slug}]: "
  new_slug="${new_slug:-$slug}"
  if ! _claude_subscription_validate_slug "$new_slug"; then
    print -u2 -r -- "Command suffix must use lowercase letters, numbers, and internal hyphens only."
    return 1
  fi

  if [[ "$new_slug" != "$slug" ]]; then
    if [[ -n "${_CLAUDE_SUBSCRIPTION_LABELS[$new_slug]-}" ]]; then
      print -u2 -r -- "Subscription command suffix already exists: ${new_slug}"
      return 1
    fi

    command_name="claude-${new_slug}"
    if (( ${+functions[$command_name]} || ${+aliases[$command_name]} || ${+commands[$command_name]} )); then
      print -u2 -r -- "Command name is already in use: ${command_name}"
      return 1
    fi
    _claude_subscription_remove_executable "$slug"
  fi

  tmp="${CLAUDE_SUBSCRIPTIONS_FILE}.tmp.$$"
  : > "$tmp" || return 1
  while IFS=$'\t' read -r current_slug current_label current_service extra; do
    if [[ "$current_slug" == "$slug" ]]; then
      printf '%s\t%s\t%s\n' "$new_slug" "$new_label" "$service" >> "$tmp"
    else
      printf '%s\t%s\t%s\n' "$current_slug" "$current_label" "$current_service" >> "$tmp"
    fi
  done < "$CLAUDE_SUBSCRIPTIONS_FILE"
  mv "$tmp" "$CLAUDE_SUBSCRIPTIONS_FILE" || return 1
  chmod 600 "$CLAUDE_SUBSCRIPTIONS_FILE" 2>/dev/null

  _claude_subscriptions_reload
  print -r -- "Updated ${old_label} to ${new_label}."
  print -r -- "Direct command: claude-${new_slug}"
}

_claude_accounts_pick() {
  local slug label service state usage selected item
  local -a choices=("__add__\t+ Add subscription\tCreate a Keychain-backed Claude account")
  local -a fallback_choices=("+ Add subscription")

  for slug in "${_CLAUDE_SUBSCRIPTION_SLUGS[@]}"; do
    label="${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}"
    service="${_CLAUDE_SUBSCRIPTION_SERVICES[$slug]}"
    if _claude_subscription_is_configured "$service"; then
      state="configured"
    else
      state="token missing"
    fi
    _claude_subscription_usage_summary "$slug"
    usage="$REPLY"
    choices+=("${slug}\t${label}\t${state}\t${usage}\tclaude-${slug}")
    fallback_choices+=("${label} [claude-${slug}] (${state}; ${usage})")
  done

  if (( ${+commands[fzf]} )); then
    selected="$(printf '%b\n' "${choices[@]}" | fzf \
      --prompt='Claude accounts > ' \
      --header='Select an account to manage or launch' \
      --height=50% \
      --layout=reverse \
      --border \
      --no-multi \
      --with-nth=2..)" || return 1
    REPLY="${selected%%$'\t'*}"
    return 0
  fi

  print -r -- "Claude accounts:"
  select item in "${fallback_choices[@]}" "Cancel"; do
    if (( REPLY == ${#fallback_choices[@]} + 1 )); then
      return 1
    fi
    if (( REPLY == 1 )); then
      REPLY="__add__"
      return 0
    fi
    if (( REPLY >= 2 && REPLY <= ${#fallback_choices[@]} )); then
      REPLY="${_CLAUDE_SUBSCRIPTION_SLUGS[$(( REPLY - 1 ))]}"
      return 0
    fi
    print -u2 -r -- "Invalid selection."
  done
}

_claude_account_action_pick() {
  local label="$1"
  local selected item
  local -a actions=(
    "launch\tLaunch\tStart Claude with this subscription"
    "edit\tEdit\tChange the display name or direct command"
    "refresh\tRefresh token\tGenerate and store a replacement token"
    "remove\tRemove\tDelete this subscription and its Keychain token"
    "back\tBack\tReturn to the account list"
  )

  if (( ${+commands[fzf]} )); then
    selected="$(printf '%b\n' "${actions[@]}" | fzf \
      --prompt="${label} > " \
      --header='Choose an action' \
      --height=40% \
      --layout=reverse \
      --border \
      --no-multi \
      --with-nth=2..)" || return 1
    REPLY="${selected%%$'\t'*}"
    return 0
  fi

  print -r -- "Manage ${label}:"
  select item in "Launch" "Edit" "Refresh token" "Remove" "Back" "Cancel"; do
    case "$REPLY" in
      1) REPLY="launch"; return 0 ;;
      2) REPLY="edit"; return 0 ;;
      3) REPLY="refresh"; return 0 ;;
      4) REPLY="remove"; return 0 ;;
      5) REPLY="back"; return 0 ;;
      6) return 1 ;;
      *) print -u2 -r -- "Invalid selection." ;;
    esac
  done
}

claude-accounts() {
  local slug label action

  while true; do
    _claude_accounts_pick || return 0
    slug="$REPLY"

    if [[ "$slug" == "__add__" ]]; then
      _claude_subscription_add || return 1
      continue
    fi

    label="${_CLAUDE_SUBSCRIPTION_LABELS[$slug]}"
    _claude_account_action_pick "$label" || return 0
    action="$REPLY"

    case "$action" in
      launch)
        _claude_subscription_run "$slug" "$@"
        return $?
        ;;
      edit)
        _claude_subscription_edit "$slug" || return 1
        ;;
      refresh)
        _claude_subscription_add "$slug" || return 1
        ;;
      remove)
        _claude_subscription_remove "$slug" || return 1
        ;;
      back)
        ;;
    esac
  done
}

# Remove commands from earlier implementations when re-sourced.
unfunction \
  claude-a \
  claude-b \
  claude-select \
  claude-use \
  claude-auth-add \
  claude-auth-list \
  claude-auth-remove \
  claude-subscriptions-reload 2>/dev/null || true

_claude_subscriptions_reload
