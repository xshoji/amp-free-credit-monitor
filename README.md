# Amp Free Credit Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that displays your [Amp](https://ampcode.com/) Free credit balance in the macOS menu bar.

<img width="686" height="403" alt="xshoji_amp-free-credit-monitor_ss" src="https://github.com/user-attachments/assets/abdda213-d05e-4ac9-9e49-a7421b2f3543" />


## Overview

This is a standalone SwiftBar plugin — no additional Amp plugins required.

```
┌─────────────────────────────────────────┐
│  SwiftBar Plugin (bash)                 │
│  amp-free-credit-monitor.10s.sh         │
│                                         │
│  • Auto-refresh every 10 seconds        │
│  • Amp running  → fetch via `amp usage` │
│  • Amp stopped  → show cached data      │
│  • Wake / hourly → force refresh        │
│  • Cache results as JSON                │
└─────────────────────────────────────────┘
```

### Menu Bar Preview

```
[Logo] Free $5.44  ← Normal
[Logo] Free $1.20  ← Low balance (orange)
[Logo] Free $0.30  ← Critical (red)
```

## Prerequisites

- **macOS**
- **Amp CLI** (binary installation — `npm install` version is not supported)
- **[SwiftBar](https://github.com/swiftbar/SwiftBar)**

## Installation

> **Note:** If SwiftBar is already installed and the plugin directory is configured, skip to step 3.

### 1. Install SwiftBar

```bash
brew install --cask swiftbar
```

### 2. Configure the SwiftBar plugin directory

```bash
mkdir -p ~/.config/swiftbar
defaults write com.ameba.SwiftBar PluginDirectory "$HOME/.config/swiftbar"
```

### 3. Link the plugin

```bash
ln -sf "$(pwd)/amp-free-credit-monitor.10s.sh" ~/.config/swiftbar/amp-free-credit-monitor.10s.sh
```

### 4. Launch SwiftBar

```bash
open -a SwiftBar
```

> **Note:** You may need to restart SwiftBar after the initial launch or after running `defaults write`.

## How It Works

### When Amp is running

1. SwiftBar executes the script every 10 seconds.
2. The script checks for the Amp process via `ps`.
3. Runs `amp usage` to fetch current credit information.
4. Saves the result as JSON to `/tmp/amp-credit-menubar.txt`.
5. Displays the remaining balance in the menu bar.

### When Amp is not running

- Displays the cached value from the last successful fetch (credit doesn't decrease while Amp is idle, so the cached value stays accurate).
- On sleep/wake recovery (within 60 seconds) or at the 1st minute of each hour, the script force-runs `amp usage` to refresh.

## Cache File Format

The cache is stored at `/tmp/amp-credit-menubar.txt` in JSON format:

```json
{
  "remaining": 5.44,
  "limit": 10,
  "replenishRate": 0.42,
  "showLimit": false,
  "updatedAt": "2026-04-02T07:16:41Z"
}
```

## Configuration

| Setting | How to change |
|---|---|
| Refresh interval | Rename the file (e.g., `1m` suffix for 1-minute interval) |
| Color thresholds | Edit `CRITICAL_BALANCE_THRESHOLD` / `LOW_BALANCE_THRESHOLD` in the script (`≤ $0.50` → red, `≤ $1.50` → orange) |
| Cache file path | Set the `AMP_CREDIT_FILE` environment variable (default: `/tmp/amp-credit-menubar.txt`) |
| Menu bar icon | Set `AMP_ICON_BASE64` to a base64-encoded PNG to override the bundled `amp` icon |

## Troubleshooting

### Nothing appears in the menu bar

1. Verify SwiftBar is running: `pgrep -l SwiftBar`
2. Check the plugin directory: `defaults read com.ameba.SwiftBar PluginDirectory`
3. Run the script manually: `bash ~/.config/swiftbar/amp-free-credit-monitor.10s.sh`
4. Restart SwiftBar: `killall SwiftBar; open -a SwiftBar`

### `amp usage` fails

- Confirm the `amp` binary path: `which amp`
- Ensure you are logged in: run `amp usage` directly in a terminal.

### Known Limitations

- The script parses `amp usage` output with regex. If the output format changes in a future Amp update, parsing may break.

## License

[MIT](LICENSE)
