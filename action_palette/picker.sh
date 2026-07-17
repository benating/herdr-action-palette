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

# Execute the action
printf 'Executing: %s\n' "$action_cmd"
if eval "$action_cmd"; then
  printf 'Action completed successfully.\n'
  exit 0
else
  die "action-palette: command failed
${action_cmd}"
fi
