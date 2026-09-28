# Herdr Action Palette

A fuzzy-searchable action palette plugin for Herdr that lets you quickly find and execute any Herdr default action.

## Features

- **Fuzzy Search**: Use fzf to quickly find any action by name or description
- **Popup Interface**: Opens in a compact 60%x40% popup window that doesn't disrupt your workflow
- **Comprehensive Actions**: Covers all major Herdr actions including pane, tab, workspace, and navigation commands
- **Honest About Limits**: Actions that Herdr only exposes as client-side key presses (detach, sidebar, goto) show the chord to press instead of erroring out
- **Keyboard Accessible**: Bind to any key combination (default: `prefix+f`)

## Installation

### Option 1: Link for Local Development

```bash
# Navigate to this plugin directory
cd /path/to/action_palette/action_palette

# Link the plugin
herdr plugin link $(pwd)

# Verify the plugin is registered
herdr plugin list
```

### Option 2: Install from GitHub

Once this plugin is hosted on GitHub:

```bash
herdr plugin install your-username/herdr-action-palette
```

## Configuration

### Step 1: Add Keybinding

Add the following to your `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+f"
type = "plugin_action"
command = "herdr.action_palette.open"
description = "Open action palette"
```

### Step 2: Reload Configuration

```bash
herdr server reload-config
```

### Alternative Keybindings

You can bind the action palette to any key combination. Some suggestions:

```toml
# Direct access (no prefix) - make sure the chord is safe in your terminal
[[keys.command]]
key = "ctrl+alt+f"
type = "plugin_action"
command = "herdr.action_palette.open"
description = "Open action palette"

# Or use a different prefix combination
[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "herdr.action_palette.open"
description = "Open action palette"
```

## Usage

1. Press your configured keybinding (default: `prefix+f`)
2. A compact popup will appear with a searchable list of all available actions
3. Type to fuzzy-search for an action
4. Press Enter to execute the selected action
5. Read-only actions (info, lists, status) and keybinding hints wait for a keypress, so there is time to read them
6. Press Esc to cancel

## Available Actions

Throughout, *current* means the pane/tab/workspace that was focused when you
**opened the palette** — not the palette popup itself. `open.sh` forwards that
origin context to the popup, so `Split Pane Right` splits your pane rather than
the picker.

### Pane Actions (15 actions)
| Action | Description |
|--------|-------------|
| Split Pane Right | Split the current pane vertically |
| Split Pane Down | Split the current pane horizontally |
| Close Pane | Close the current pane |
| Zoom Pane (Toggle) | Toggle zoom for the current pane |
| Focus Pane Left/Right/Up/Down | Navigate between panes |
| Swap Pane Left/Right/Up/Down | Swap position with neighboring panes |
| Show Pane Layout | Display the current pane layout |
| Show Pane Info | Display detailed info about the current pane |
| Rename Pane | Rename the current pane |

### Tab Actions (6 actions)
| Action | Description |
|--------|-------------|
| New Tab | Create a new tab |
| Close Tab | Close the current tab |
| List Tabs | List all tabs in current workspace |
| Show Tab Info | Display detailed info about the current tab |
| Focus First Tab | Focus the first tab in the workspace |
| Rename Tab | Rename the current tab |

### Workspace Actions (5 actions)
| Action | Description |
|--------|-------------|
| New Workspace | Create a new workspace |
| Close Workspace | Close the current workspace |
| List Workspaces | List all workspaces |
| Show Workspace Info | Display detailed info about the current workspace |
| Rename Workspace | Rename the current workspace |

### Navigation (2 actions)
| Action | Description |
|--------|-------------|
| Go To Picker † | Open workspace/tab/pane picker |
| Toggle Sidebar † | Toggle the sidebar visibility |

### Session (3 actions)
| Action | Description |
|--------|-------------|
| Detach † | Detach from the current session (leave running) |
| Show Status | Show server and client status |
| Reload Config | Reload configuration from config.toml |

**Total: 31 actions**

† **Client-only actions.** These have no Herdr CLI or socket command, so the
palette shows the configured keybinding instead of failing — see
[Client-only actions](#client-only-actions).

## Client-only actions

Herdr splits its surface in two:

- **CLI + socket API** (`herdr pane …`, `herdr tab …`, `herdr workspace …`,
  `server.reload_config`, …) — anything a plugin can call.
- **Client-side key actions** (`[keys]` in `config.toml`) — detach, goto,
  workspace picker, toggle sidebar, resize mode, copy mode, navigate mode. These
  are handled by the attached client's input loop. There is no CLI subcommand and
  no socket method for them, so *no* command palette can invoke them. An upstream
  [discussion #3880](https://github.com/herdrdev/herdr/discussions/3880) asks for
  a `herdr detach` command; it does not exist through 0.9.1.

Rather than exiting with `unknown command: detach`, these entries close the
search and print the chord from *your* `config.toml` (falling back to Herdr's
built-in defaults), for example:

```
── Detach ──

Herdr has no CLI or socket command for this one — it is a client-side
key action, so no command palette can invoke it for you. Press instead:

    ctrl+b q

Every pane keeps running. Reattach later with: herdr
```

If you disabled one (`detach = ""`), the popup says so and points at the file.
This is the intended behaviour, not a bug. If/when Herdr adds these commands to
the CLI, swap the `@hint:<name>` entries in `actions.json` for real commands.

## Requirements

- **Herdr** >= 0.7.0 (verified against 0.8.0)
- **bash** 3.2+ (macOS default is fine)
- **fzf** - Fuzzy finder (https://github.com/junegunn/fzf)
- **jq** - JSON processor (https://github.com/jq/jq)

### Installing Dependencies

**macOS:**
```bash
brew install fzf jq
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt install fzf jq
```

## Development

### Plugin Structure

```
action_palette/
├── herdr-plugin.toml   # Plugin manifest
├── open.sh             # Opens the overlay pane
├── picker.sh           # Main fzf picker script (runs in overlay)
├── actions.json        # List of available actions
├── keybinding.toml     # Example keybinding configuration
├── README.md           # This file
└── .gitignore          # Git ignore rules
```

### How It Works

1. **open.sh**: When invoked via the `herdr.action_palette.open` action, this script opens a popup pane (60%x40%). It runs on the Herdr server without a TTY, so it can't run fzf directly.

2. **picker.sh**: This script runs inside the popup pane which has a real TTY. It loads actions from `actions.json`, displays them in fzf, resolves the selected command, and executes it.

### Targeting: placeholders, not `--current`

While the popup is open it holds the focus, and a plugin pane is *not* given a
`HERDR_PANE_ID`, so `--current` and "focused" lookups are ambiguous at best. Each
command therefore names its target explicitly. `picker.sh` resolves these
placeholders (source order: forwarded env → the popup's own
`HERDR_PLUGIN_CONTEXT_JSON` → a live `herdr` query):

| Placeholder | Resolves to |
|-------------|-------------|
| `@pane`, `@tab`, `@workspace` | the pane/tab/workspace focused when the palette was opened |
| `@first_tab` | lowest-numbered tab in that workspace |
| `@cwd` | cwd of the pane the palette was opened from |
| `@label` | prompts for text; empty input cancels |
| `@label_or_clear` | prompts for text; empty input sends `--clear` |
| `@show` (leading) | read-only action — keep the popup open so the output can be read |
| `@hint:<keys_action>` | client-only action — print the chord, see above |

Commands are split into argv and executed directly (never `eval`), and ids are
validated against Herdr's `[A-Za-z0-9_.:-]` id charset before they reach argv.

### Adding New Actions

1. Edit `actions.json` and add a new action entry:

```json
{
  "id": "my_new_action",
  "name": "My New Action",
  "description": "What this action does",
  "command": "herdr some-command --pane @pane --options"
}
```

2. Add it to the appropriate category in the JSON file
3. Dry-run it (below) to confirm the argv resolves, then test it live

Only `herdr …` commands and `@hint:…` entries are accepted. Write argv tokens,
not shell: no pipes, quotes, `$(…)`, or `--current`.

> `--current` exists on some subcommands (`pane split`, `zoom`, `focus`, `swap`,
> `layout`) and **not** on others (`pane get/close/rename`, `tab get/close/focus`,
> `workspace get/close/rename` take a positional id). Even where it works, prefer
> `@pane` / `@tab` / `@workspace` so the action targets the user's pane and not
> the palette popup.

### Testing

To test the plugin without setting up keybindings:

```bash
# Invoke the action directly
herdr plugin action invoke herdr.action_palette.open
```

### Dry run

`HERDR_ACTION_PALETTE_DRY_RUN=1` makes `picker.sh` print the resolved command
instead of running it, so you can check what a change would touch. Run it where
`fzf` and `jq` resolve, with `stdin` attached to the popup or a pipe:

```bash
export HERDR_ACTION_PALETTE_DRY_RUN=1
# optional: override the origin context the palette acts on
export HERDR_ACTION_PALETTE_PANE_ID=w1:p1
export HERDR_ACTION_PALETTE_TAB_ID=w1:t1
export HERDR_ACTION_PALETTE_WORKSPACE_ID=w1
bash picker.sh
# -> DRY RUN: herdr pane close w1:p1
```

### Testing Individual Actions

You can test individual Herdr commands to make sure they work. Note the split
between option-style and positional targets:

```bash
# Option-style target (accepts --pane / --current)
herdr pane split --pane "$HERDR_PANE_ID" --direction right
herdr pane zoom  --pane "$HERDR_PANE_ID" --toggle
herdr pane layout --pane "$HERDR_PANE_ID"

# Positional target (no --current exists here)
herdr pane get   "$HERDR_PANE_ID"
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr tab get  "$HERDR_TAB_ID"
herdr workspace list

# These are NOT herdr commands — see "Client-only actions"
herdr detach            # unknown command: detach
herdr goto picker       # unknown command: goto
herdr ui toggle-sidebar # unknown command: ui
```

## Troubleshooting

### fzf not found
Install fzf using your package manager (see Requirements section).

### jq not found
Install jq using your package manager (see Requirements section).

### Keybinding doesn't work
1. Make sure the plugin is linked/installed: `herdr plugin list`
2. Check your config.toml syntax: `herdr config check`
3. Reload the config: `herdr server reload-config`
4. Check if the keybinding is being consumed by your terminal

### Popup doesn't appear
1. Check that Herdr version is >= 0.7.0: `herdr --version`
2. Make sure no other modal (Settings, Copy mode, another popup) is active
3. Check Herdr logs: `cat ~/.config/herdr/herdr.log`

### Action fails to execute
1. Dry-run it first: `HERDR_ACTION_PALETTE_DRY_RUN=1 bash picker.sh` shows the exact argv
2. Check if the command is correct by running it manually (`herdr <group> --help` is the authority)
3. Some actions need context — a stale `@pane` (closed since the palette opened) reports `pane_not_found`
4. `unknown command` means the action invented a CLI command Herdr does not have; client-side key actions belong in `@hint:` form
5. Check Herdr logs: `cat ~/.config/herdr/herdr.log`

### Detach / Toggle Sidebar / Go To Picker only show a keybinding

Expected — Herdr has no CLI or socket command for those. See
[Client-only actions](#client-only-actions).

## License

MIT License - feel free to use and modify as needed.

## Contributing

Contributions are welcome! Feel free to:
- Add new actions to the palette
- Improve the UI/UX
- Fix bugs
- Add documentation

## Credits

Built for [Herdr](https://herdr.dev) - the terminal workspace manager for AI coding agents.

Inspired by [JanTvrdik/herdr-command-palette](https://github.com/JanTvrdik/herdr-command-palette).
