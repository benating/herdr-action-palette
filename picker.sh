#!/usr/bin/env bash
# Pane `herdr.action_palette.palette`: the interactive fzf picker.
#
# Runs inside a popup pane (real TTY). Lists all actions from actions.json,
# lets the user fuzzy-pick one, and invokes it. When this script exits the
# popup closes on its own.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
self_plugin="${HERDR_PLUGIN_ID:-herdr.action_palette}"
plugin_root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Brief pause + message helper so failures don't vanish when the overlay closes.
die() {
  printf '%s\n' "$*" >&2
  printf 'Press any key to close…' >&2
  read -r -n1 _ 2>/dev/null || sleep 2
  exit 1
}

command -v fzf >/dev/null 2>&1 || die "action-palette: fzf is not installed or not on PATH."
command -v jq  >/dev/null 2>&1 || die "action-palette: jq is not installed or not on PATH."

# Build action list from actions.json
actions_file="${plugin_root}/actions.json"
[ -f "$actions_file" ] || die "action-palette: actions.json not found at ${actions_file}"

# Each line: "action_name\tcommand"
# Field 1 is what we display; field 2 is the command to run
lines="$(
  jq -r 'to_entries[] | .key as $cat | .value[] | "\(.name)\t\(.command)"' "$actions_file" 2>/dev/null \
    | sort -t$'\t' -k1,1
)"

[ -n "$lines" ] || die "action-palette: no actions available."

# fzf: display field 1, but match against the whole line (so typing command works too)
# Esc/Ctrl-C abort → empty selection → silent close
choice="$(
  printf '%s\n' "$lines" \
    | fzf --delimiter=$'\t' \
          --with-nth=1 \
          --prompt='herdr action ▸ ' \
          --header='↑↓ select · enter run · esc cancel' \
          --reverse \
          --cycle \
          --no-multi \
          --no-sort
)" || true

[ -n "$choice" ] || exit 0

# Extract the command (field 2)
action_cmd="$(printf '%s' "$choice" | cut -f2)"

[ -n "$action_cmd" ] || die "action-palette: could not extract command from selection."

# Handle special actions that require getting current ID first
handle_close_pane_action() {
  local current_id
  current_id="$(herdr pane current --current 2>/dev/null | jq -r '.result.pane.pane_id' 2>/dev/null)"
  
  [ -n "$current_id" ] && [ "$current_id" != "null" ] || die "action-palette: could not get current pane ID. Make sure you have a pane open."
  
  printf 'Executing: herdr pane close %s\n' "$current_id"
  herdr pane close "$current_id"
}

# Handle special rename actions that require interactive label input
handle_rename_action() {
  local action_type="$1"
  local current_id
  local label

  # Get the current ID based on action type
  case "$action_type" in
    tab)
      # herdr tab get --current doesn't work, use list and filter focused
      current_id="$(herdr tab list 2>/dev/null | jq -r '.result.tabs[] | select(.focused) | .tab_id' 2>/dev/null)"
      ;;
    workspace)
      # herdr workspace get --current doesn't work, use list and filter focused
      current_id="$(herdr workspace list 2>/dev/null | jq -r '.result.workspaces[] | select(.focused) | .workspace_id' 2>/dev/null)"
      ;;
    pane)
      current_id="$(herdr pane current --current 2>/dev/null | jq -r '.result.pane.pane_id' 2>/dev/null)"
      ;;
    *)
      die "action-palette: unknown rename action type: $action_type"
      ;;
  esac

  [ -n "$current_id" ] && [ "$current_id" != "null" ] || die "action-palette: could not get current $action_type ID. Make sure you have a $action_type open."

  # Prompt for the new label
  printf 'Enter new %s label [%s]: ' "$action_type" "$current_id" >&2
  read -r label || die "action-palette: cancelled"

  # If empty label, use the ID as-is (or clear for pane)
  if [ -z "$label" ]; then
    if [ "$action_type" = "pane" ]; then
      label="--clear"
    else
      printf 'action-palette: label cannot be empty, cancelled.\n'
      exit 0
    fi
  fi

  # Execute the appropriate rename command
  case "$action_type" in
    tab)
      printf 'Executing: herdr tab rename %s "%s"\n' "$current_id" "$label"
      herdr tab rename "$current_id" "$label"
      ;;
    workspace)
      printf 'Executing: herdr workspace rename %s "%s"\n' "$current_id" "$label"
      herdr workspace rename "$current_id" "$label"
      ;;
    pane)
      printf 'Executing: herdr pane rename %s "%s"\n' "$current_id" "$label"
      herdr pane rename "$current_id" "$label"
      ;;
  esac
}

# Check if this is a special action and handle accordingly
case "$action_cmd" in
  herdr_action_palette_close_pane)
    handle_close_pane_action
    exit $?
    ;;
  herdr_action_palette_rename_tab)
    handle_rename_action "tab"
    exit $?
    ;;
  herdr_action_palette_rename_workspace)
    handle_rename_action "workspace"
    exit $?
    ;;
  herdr_action_palette_rename_pane)
    handle_rename_action "pane"
    exit $?
    ;;
  *)
    # Execute regular action
    printf 'Executing: %s\n' "$action_cmd"
    if eval "$action_cmd"; then
      printf 'Action completed successfully.\n'
      exit 0
    else
      die "action-palette: command failed
${action_cmd}"
    fi
    ;;
esac
