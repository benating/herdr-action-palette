#!/usr/bin/env bash
# Action `herdr.action_palette.open`: open the fzf action-palette popup.
#
# This runs on the herdr server (no TTY), so it can't run fzf directly. It opens
# the `palette` popup pane (see herdr-plugin.toml), which gets a real terminal
# and runs picker.sh.
#
# The popup takes focus, so once picker.sh runs, the calling pane is the POPUP —
# `--current` and "focused" lookups would target the palette itself. To keep the
# palette acting on the pane the user was actually in, we forward that origin
# context (from HERDR_PLUGIN_CONTEXT_JSON) to the popup as env, along with its
# cwd.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

# Pull one field out of the invocation context.
ctx_get() {
  local field="$1"
  [ -n "$ctx" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$ctx" | jq -r ".$field // empty" 2>/dev/null || true
}

# herdr ids are opaque `[A-Za-z0-9_.:-]` handles; drop anything else so a
# surprising reply can never turn into an option or a broken path.
clean_id() {
  local id="${1:-}"
  case "$id" in
    "" | null | -* | *[!A-Za-z0-9_.:-]*) printf '' ;;
    *) printf '%s' "$id" ;;
  esac
}

origin_pane="$(clean_id "$(ctx_get focused_pane_id)")"
origin_tab="$(clean_id "$(ctx_get tab_id)")"
origin_workspace="$(clean_id "$(ctx_get workspace_id)")"

# Resolve the repo/dir the user triggered the palette from.
repo="$(ctx_get focused_pane_cwd)"
[ -n "$repo" ] || repo="$(ctx_get workspace_cwd)"
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr.action_palette \
  --entrypoint palette \
  --placement popup \
  --width 60% \
  --height 40% \
  --focus

# Only forward --cwd when it's a real directory; otherwise the overlay falls
# back to the plugin root (the pane command uses $HERDR_PLUGIN_ROOT, so it
# resolves either way).
if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --cwd "$repo"
  set -- "$@" --env "HERDR_ACTION_PALETTE_CWD=$repo"
fi

# Origin targets for the @pane / @tab / @workspace placeholders in actions.json.
[ -n "$origin_pane" ] && set -- "$@" --env "HERDR_ACTION_PALETTE_PANE_ID=$origin_pane"
[ -n "$origin_tab" ] && set -- "$@" --env "HERDR_ACTION_PALETTE_TAB_ID=$origin_tab"
[ -n "$origin_workspace" ] && set -- "$@" --env "HERDR_ACTION_PALETTE_WORKSPACE_ID=$origin_workspace"

exec "$herdr_bin" "$@"