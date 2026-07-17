# Herdr Action Palette

A fuzzy-searchable action palette plugin for Herdr that lets you quickly find and execute any Herdr default action.

## Features

- **Fuzzy Search**: Use fzf to quickly find any action by name or description
- **Popup Interface**: Opens in a compact 60%x40% popup window that doesn't disrupt your workflow
- **Comprehensive Actions**: Covers all major Herdr actions including pane, tab, workspace, and navigation commands
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
5. Press Esc to cancel

## Available Actions

### Pane Actions (14 actions)
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

### Tab Actions (5 actions)
| Action | Description |
|--------|-------------|
| New Tab | Create a new tab |
| Close Tab | Close the current tab |
| List Tabs | List all tabs in current workspace |
| Show Tab Info | Display detailed info about the current tab |
| Focus First Tab | Focus the first tab in the workspace |

### Workspace Actions (4 actions)
| Action | Description |
|--------|-------------|
| New Workspace | Create a new workspace |
| Close Workspace | Close the current workspace |
| List Workspaces | List all workspaces |
| Show Workspace Info | Display detailed info about the current workspace |

### Navigation (2 actions)
| Action | Description |
|--------|-------------|
| Go To Picker | Open workspace/tab/pane picker |
| Toggle Sidebar | Toggle the sidebar visibility |

### Session (3 actions)
| Action | Description |
|--------|-------------|
| Detach | Detach from the current session |
| Show Status | Show server and client status |
| Reload Config | Reload configuration from config.toml |

**Total: 28 actions**

## Requirements

- **Herdr** >= 0.7.0
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

2. **picker.sh**: This script runs inside the popup pane which has a real TTY. It loads actions from `actions.json`, displays them in fzf, and executes the selected action.

### Adding New Actions

1. Edit `actions.json` and add a new action entry:

```json
{
  "id": "my_new_action",
  "name": "My New Action",
  "description": "What this action does",
  "command": "herdr some-command --options"
}
```

2. Add it to the appropriate category in the JSON file
3. Test the action to make sure it works

### Testing

To test the plugin without setting up keybindings:

```bash
# Invoke the action directly
herdr plugin action invoke herdr.action_palette.open
```

### Testing Individual Actions

You can test individual Herdr commands to make sure they work:

```bash
# Test pane split
herdr pane split --current --direction right

# Test tab creation
herdr tab create

# Test workspace list
herdr workspace list
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
1. Check if the command is correct by running it manually
2. Some actions may require specific context (e.g., pane focus)
3. Check Herdr logs: `cat ~/.config/herdr/herdr.log`

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
