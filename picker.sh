#!/usr/bin/env bash
# Pane `herdr.action_palette.palette`: the interactive fzf picker.
#
# Runs inside a popup pane (real TTY). Lists all actions from actions.json,
# lets the user fuzzy-pick one, and runs it. When this script exits the popup
# closes on its own.
#
# Commands in actions.json are argv, never shell (no `eval`), and may carry
# placeholders that are resolved before the command runs:
#
#   @pane, @tab, @workspace  the pane/tab/workspace that was focused when the
#                            palette was OPENED. Avoid `--current`: this popup
#                            holds the focus while it runs (and a plugin pane is
#                            given no HERDR_PANE_ID at all), so `--current` can
#                            resolve to the palette instead of the user's pane —
#                            splitting, zooming, or closing the picker.
#   @first_tab               lowest-numbered tab in the resolved workspace
#   @cwd                     cwd of the pane the palette was opened from
#   @label                   prompt for text; empty input cancels
#   @label_or_clear          prompt for text; empty input sends `--clear`
#   @show                    leading marker: read-only action, keep the popup
#                            open so the output can actually be read
#   @hint:<keys_action>      Herdr exposes this only as a client-side key
#                            action (no CLI/socket command), so show the
#                            configured chord instead of failing. See README.
#
# Development: HERDR_ACTION_PALETTE_DRY_RUN=1 prints the resolved command
# instead of running it.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
plugin_root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
dry_run="${HERDR_ACTION_PALETTE_DRY_RUN:-}"

# Origin context forwarded by open.sh via `plugin pane open --env`.
origin_pane="${HERDR_ACTION_PALETTE_PANE_ID:-}"
origin_tab="${HERDR_ACTION_PALETTE_TAB_ID:-}"
origin_workspace="${HERDR_ACTION_PALETTE_WORKSPACE_ID:-}"
origin_cwd="${HERDR_ACTION_PALETTE_CWD:-}"

# Brief pause + message helper so failures don't vanish when the overlay closes.
die() {
  printf '%s\n' "$*" >&2
  printf 'Press any key to close…' >&2
  read -r -n1 _ 2>/dev/null || sleep 2
  exit 1
}

command -v fzf >/dev/null 2>&1 || die "action-palette: fzf is not installed or not on PATH."
command -v jq  >/dev/null 2>&1 || die "action-palette: jq is not installed or not on PATH."

# ---------------------------------------------------------------------------
# target resolution
# ---------------------------------------------------------------------------

# Run a herdr command and pull one value out of its JSON reply.
# usage: herdr_query <jq-filter> <herdr args...>
herdr_query() {
  local filter="$1"
  shift
  "$herdr_bin" "$@" 2>/dev/null | jq -r "$filter" 2>/dev/null | head -n1
}

# Herdr hands this popup its own invocation context (a plugin pane gets no
# HERDR_PANE_ID). That context still names the pane/tab/workspace that were
# focused when the palette was opened, so it is a good second source.
popup_ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
ctx_get() {
  local field="$1"
  [ -n "$popup_ctx" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$popup_ctx" | jq -r ".$field // empty" 2>/dev/null || true
}

# Public herdr ids are opaque `[A-Za-z0-9_.:-]` handles. Echo the id, or fail on
# anything empty / null / flag-shaped, so a surprising reply can never reach
# argv as an option.
clean_id() {
  local id="${1:-}"
  case "$id" in
    "" | null | -* | *[!A-Za-z0-9_.:-]*) return 1 ;;
  esac
  printf '%s' "$id"
}

resolve_pane_id() {
  local id
  clean_id "$origin_pane" && return 0
  clean_id "$(ctx_get focused_pane_id)" && return 0
  id="$(herdr_query '.result.pane.pane_id' pane current --current)"
  clean_id "$id"
}

resolve_workspace_id() {
  local id
  clean_id "$origin_workspace" && return 0
  clean_id "$(ctx_get workspace_id)" && return 0
  id="$(herdr_query '.result.workspaces[] | select(.focused) | .workspace_id' workspace list)"
  clean_id "$id"
}

resolve_tab_id() {
  local id ws
  clean_id "$origin_tab" && return 0
  clean_id "$(ctx_get tab_id)" && return 0
  ws="$(resolve_workspace_id)" || ws=""
  [ -n "$ws" ] || return 1
  id="$(herdr_query '.result.tabs[] | select(.focused) | .tab_id' tab list --workspace "$ws")"
  clean_id "$id"
}

resolve_first_tab_id() {
  local id ws
  ws="$(resolve_workspace_id)" || ws=""
  [ -n "$ws" ] || return 1
  id="$(herdr_query '.result.tabs | min_by(.number) | .tab_id' tab list --workspace "$ws")"
  clean_id "$id"
}

# ---------------------------------------------------------------------------
# keybinding hints (client-side actions herdr has no CLI for)
# ---------------------------------------------------------------------------

herdr_config_path() {
  if [ -n "${HERDR_CONFIG_PATH:-}" ]; then
    printf '%s' "$HERDR_CONFIG_PATH"
  else
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"
  fi
}

# Print the value of `name = "…"` inside the [keys] table. Exit 1 when the key
# is absent, which is different from an explicit `name = ""` (disabled).
# `[keys.command]` is a separate table and is deliberately not matched.
keys_value() {
  local name="$1" cfg
  cfg="$(herdr_config_path)"
  [ -f "$cfg" ] || return 1
  awk -v want="$name" '
    /^[[:space:]]*\[/ { inkeys = ($0 ~ /^[[:space:]]*\[keys\][[:space:]]*$/); next }
    !inkeys { next }
    /^[[:space:]]*#/ { next }
    match($0, "^[[:space:]]*" want "[[:space:]]*=[[:space:]]*\"") {
      v = substr($0, RSTART + RLENGTH); sub(/".*/, "", v); last = v; found = 1
    }
    END { if (!found) exit 1; printf "%s", last }
  ' "$cfg"
}

# Built-in chords from `herdr --default-config`, used when config is silent.
default_chord() {
  case "$1" in
    detach) printf 'prefix+q' ;;
    goto) printf 'prefix+g' ;;
    workspace_picker) printf 'prefix+w' ;;
    toggle_sidebar) printf 'prefix+b' ;;
    *) return 1 ;;
  esac
}

# Print a readable chord ("prefix+q" -> "ctrl+b q").
# exit 0 = printed, 1 = explicitly unbound in config, 2 = no chord known.
keys_chord() {
  local name="$1" raw chord prefix
  if raw="$(keys_value "$name")"; then
    [ -n "$raw" ] || return 1
    chord="$raw"
  else
    chord="$(default_chord "$name")" || return 2
  fi
  prefix="$(keys_value prefix)" || prefix="ctrl+b"
  case "$chord" in
    prefix+*) printf '%s %s' "$prefix" "${chord#prefix+}" ;;
    *) printf '%s' "$chord" ;;
  esac
}

# Extra lines that make each hint actionable, e.g. the reattach command.
hint_note() {
  local name="$1" chord
  case "$name" in
    detach)
      if [ -n "${HERDR_SESSION:-}" ]; then
        printf 'Every pane keeps running. Reattach later with: herdr session attach %s' "$HERDR_SESSION"
      else
        printf 'Every pane keeps running. Reattach later with: herdr'
      fi
      ;;
    goto)
      chord="$(keys_chord workspace_picker)" && {
        printf 'Workspace navigation is a separate client action: %s' "$chord"
      }
      ;;
  esac
}

show_key_hint() {
  local name="$1" title="$2" chord note status
  printf '\n── %s ──\n\n' "$title"
  chord="$(keys_chord "$name")"
  status=$?
  case "$status" in
    0)
      printf '%s\n' "Herdr has no CLI or socket command for this one — it is a client-side"
      printf '%s\n' "key action, so no command palette can invoke it for you. Press instead:"
      printf '\n    %s\n\n' "$chord"
      ;;
    1)
      printf '%s\n' "Herdr has no CLI or socket command for this one, and it is disabled in"
      printf '  %s  ([keys] %s = ""). Add a chord there to use it.\n\n' "$(herdr_config_path)" "$name"
      ;;
    *)
      printf '%s\n' "Herdr has no CLI or socket command for this one, and no keybinding is"
      printf 'configured for it. Add one under [keys] in %s.\n\n' "$(herdr_config_path)"
      ;;
  esac
  # The reattach / related-key notes only make sense when there is a chord to press.
  if [ "$status" = 0 ]; then
    note="$(hint_note "$name")"
    [ -n "$note" ] && printf '%s\n\n' "$note"
  fi
  [ -n "$dry_run" ] && return 0
  printf 'Press any key to close…' >&2
  read -r -n1 _ 2>/dev/null || sleep 2
}

# ---------------------------------------------------------------------------
# action execution
# ---------------------------------------------------------------------------

TARGET_DESC=""

# Resolve placeholders into argv, then run. Args come from actions.json.
run_action() {
  local pause=0 argv=() tok value label trimmed empty_says

  if [ "${1:-}" = "@show" ]; then
    pause=1
    shift
  fi

  for tok in "$@"; do
    case "$tok" in
      @pane | @tab | @workspace | @first_tab)
        case "$tok" in
          @pane) value="$(resolve_pane_id)" || value="" ;;
          @tab) value="$(resolve_tab_id)" || value="" ;;
          @workspace) value="$(resolve_workspace_id)" || value="" ;;
          @first_tab) value="$(resolve_first_tab_id)" || value="" ;;
        esac
        [ -n "$value" ] || die "action-palette: could not resolve ${tok#@} — is Herdr running, and is that ${tok#@} still open?"
        TARGET_DESC="${tok#@} $value"
        argv+=("$value")
        ;;
      @cwd)
        [ -n "$origin_cwd" ] || origin_cwd="$(ctx_get focused_pane_cwd)"
        [ -n "$origin_cwd" ] || origin_cwd="$PWD"
        argv+=("$origin_cwd")
        ;;
      @label | @label_or_clear)
        empty_says="cancels"
        [ "$tok" = "@label_or_clear" ] && empty_says="clears the label"
        printf '\nNew label for %s (empty %s): ' "${TARGET_DESC:-this target}" "$empty_says" >&2
        if ! IFS= read -r label; then
          printf 'action-palette: cancelled.\n' >&2
          exit 0
        fi
        trimmed="${label#"${label%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [ -z "$trimmed" ]; then
          if [ "$tok" = "@label_or_clear" ]; then
            argv+=("--clear")
          else
            printf 'action-palette: empty label, cancelled.\n' >&2
            exit 0
          fi
        else
          argv+=("$trimmed")
        fi
        ;;
      @*)
        die "action-palette: unknown placeholder in actions.json: $tok"
        ;;
      *)
        argv+=("$tok")
        ;;
    esac
  done

  [ "${#argv[@]}" -gt 0 ] || die "action-palette: nothing to run."

  if [ -n "$dry_run" ]; then
    printf 'DRY RUN: %s\n' "${argv[*]}"
    return 0
  fi

  printf 'Executing: %s\n' "${argv[*]}"

  if [ "$pause" = 1 ]; then
    # Read-only action: capture it so the popup can show the result instead of
    # closing before anything is readable.
    local out
    if ! out="$("${argv[@]}" 2>&1)"; then
      [ -n "$out" ] && printf '%s\n' "$out" >&2
      die "action-palette: command failed
${argv[*]}"
    fi
    if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "$out" | jq .
    else
      printf '%s\n' "$out"
    fi
    printf '\nPress any key to close…' >&2
    read -r -n1 _ 2>/dev/null || sleep 2
    return 0
  fi

  "${argv[@]}" || die "action-palette: command failed
${argv[*]}"
  printf 'Action completed.\n'
}

# ---------------------------------------------------------------------------
# pick list
# ---------------------------------------------------------------------------

actions_file="${plugin_root}/actions.json"
[ -f "$actions_file" ] || die "action-palette: actions.json not found at ${actions_file}"

# Each line: "action_name<TAB>command". Field 1 is displayed, field 2 is run.
lines="$(
  jq -r 'to_entries[] | .value[] | "\(.name)\t\(.command)"' "$actions_file" 2>/dev/null \
    | sort -t$'\t' -k1,1
)"

[ -n "$lines" ] || die "action-palette: no actions available."

# fzf: display field 1, match name + command. Esc/Ctrl-C aborts to an empty
# selection, which closes the popup silently.
choice="$(
  printf '%s\n' "$lines" \
    | fzf --delimiter=$'\t' \
          --with-nth=1 \
          --nth=1,2 \
          --prompt='herdr action ▸ ' \
          --header='↑↓ select · enter run · esc cancel' \
          --reverse \
          --cycle \
          --no-multi \
          --no-sort
)" || true

[ -n "$choice" ] || exit 0

action_name="$(printf '%s' "$choice" | cut -f1)"
action_cmd="$(printf '%s' "$choice" | cut -f2)"

[ -n "$action_cmd" ] || die "action-palette: could not extract command from selection."

# argv, not a shell: split on whitespace only, no expansion, no eval.
tokens=()
read -r -a tokens <<<"$action_cmd"

# The leading @show marker is handled by run_action; dispatch on the real verb.
head="${tokens[0]:-}"
[ "$head" = "@show" ] && head="${tokens[1]:-}"

case "$head" in
  @hint:*)
    show_key_hint "${head#@hint:}" "${action_name:-Action}"
    exit 0
    ;;
  herdr)
    run_action "${tokens[@]}"
    exit $?
    ;;
  *)
    die "action-palette: unsupported command in actions.json:
$action_cmd"
    ;;
esac