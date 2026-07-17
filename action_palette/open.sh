#!/usr/bin/env bash
# Action `herdr.action_palette.open`: open the fzf action-palette popup.
#
# This runs on the herdr server (no TTY), so it can't run fzf directly. It opens
# the `palette` popup pane (see herdr-plugin.toml), which gets a real terminal
# and runs picker.sh.
#
# We forward the ORIGIN workspace's cwd to the popup via `--cwd`. That matters
# because when picker.sh later runs Herdr commands, the server resolves the
# context from the focused pane — which is now this popup.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

# Resolve the repo/dir the user triggered the palette from.
repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr.action_palette \
  --entrypoint palette \
  --placement popup \
  --width 60% \
  --height 40% \
  --focus

# Only forward --cwd when it's a real directory; otherwise the overlay falls back
# to the plugin root (the pane command uses $HERDR_PLUGIN_ROOT, so it resolves
# either way).
if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --cwd "$repo"
fi

exec "$herdr_bin" "$@"
