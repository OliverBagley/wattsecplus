<p align="center">
<img src="https://github.com/user-attachments/assets/ed040304-5689-4323-b9c0-c9355b9c4365" width="200"/>
</p>

# WattSec+

<p align="center">
<img src="https://github.com/user-attachments/assets/1d444659-dbe0-48d1-9368-a79d10ccf8c5"/>
</p>

A lightweight macOS menu bar app that displays real-time power consumption (watts), battery status, and system uptime. Fork of [beutton/wattsec](https://github.com/beutton/wattsec) with additional display options and a settings window.

## Features

- **Live wattage** — real-time system power draw via IOKit SMC, updated every 1, 3, or 5 seconds
- **Battery indicator** — percentage with optional charging/plugged dot, updated instantly on plug/unplug events
- **Uptime display** — days, hours, and minutes with compact format option
- **Settings window** — frosted-glass panel to configure all options without touching the menu
- **Grouped or separated items** — single combined menu bar item, or three independent items you can Command-drag to reorder
- **Font size & label case** — five sizes (XS–XL) and uppercase/lowercase units
- **Fixed or dynamic width** — prevent layout jitter when wattage crosses 100W
- **Launch at Login** via `SMAppService`

## Installation

Clone and build — no Xcode project required:

```bash
git clone https://github.com/oliverbagley/wattsecplus.git
cd wattsecplus
./build.sh
open dist/WattSecPlus.app
```

Move `WattSecPlus.app` to `/Applications` to install permanently. Enable **Launch at Login** in the settings window.

## Build

`build.sh` compiles with `swiftc` and assembles the `.app` bundle. Requires Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./build.sh                        # native arch — fast, small
./build.sh --universal            # arm64 + x86_64 via lipo
./build.sh -d                     # also package a DMG
./build.sh -s "Developer ID Application: ..." -k "KeychainProfile" -d
```

| Flag | Description |
|---|---|
| `-v, --version VERSION` | Override version (default: `VERSION` file) |
| `-u, --universal` | Build universal binary (arm64 + x86_64) |
| `-d, --create-dmg` | Package into a DMG |
| `-s, --sign ID` | Code sign with a Developer ID |
| `-k, --keychain PROFILE` | Keychain profile for notarization (used with `--sign`) |

## Settings

Open the settings window from the menu bar menu → **Settings…**

<p align="center">
<img src="https://github.com/user-attachments/assets/9d213036-225c-4369-9b18-1cb6b94956e1"/>
</p>

| Setting | Options | Default | Description |
|---|---|---|---|
| Detail | Low / Medium / High | Medium | Watt decimal places: 0 / 1 / 2 |
| Pace | 1s / 3s / 5s | 1s | SMC polling interval |
| Bar Width | Dynamic / Fixed | Dynamic | Fixed width prevents layout jitter at 100W |
| Font Size | XS / S / M / L / XL | M | Menu bar font size (10–15 pt) |
| Labels | Uppercase / Lowercase | Lowercase | Unit label case (W/w, %/%) |
| Show Battery | on/off | off | Battery percentage with charge indicator |
| Show Uptime | on/off | on | System uptime in the menu bar |
| Compact format | on/off | off | Remove spaces between uptime components |
| Always show minutes | on/off | off | Show minutes even when days are visible |
| Group into one item | on/off | on | Single combined item vs. three separate items |
| Show dash separator | on/off | off | Use ` - ` between grouped components |
| Launch at Login | on/off | off | Start WattSec+ automatically on login |

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode or Command Line Tools (for building only)

## Differences from the original WattSec

- Settings window with live preview
- Battery percentage with charge/plugged indicator
- Uptime display with compact and minutes options
- Grouped or separated menu bar items
- Font size and label case controls
- Fixed-width mode with 60-second hysteresis at 100W

## Credits

- [WattSec](https://github.com/beutton/wattsec) — original app by beutton
- [Stats](https://github.com/exelban/stats) — SMC polling reference
