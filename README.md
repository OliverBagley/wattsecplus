<p align="center">
<img src="https://github.com/user-attachments/assets/ed040304-5689-4323-b9c0-c9355b9c4365" width="200"/>
</p>

# WattSec

<p align="center">
<img src="https://github.com/user-attachments/assets/1d444659-dbe0-48d1-9368-a79d10ccf8c5"/>
</p>

Display macOS power usage (wattage) in the menu bar

## Differences in this fork

This fork adds a few minimal, optional enhancements:

- **Uptime display** in the menu bar  
- **Text customization** options for font size and letter case

All credit for the original app goes to [beutton](https://github.com/beutton/wattsec).

## Installation

WattSec can be installed with Homebrew:

```
brew tap beutton/brew
brew install wattsec
```

Alternatively, you can download the latest release [here](https://github.com/beutton/wattsec/releases/latest).

## Build

No Xcode project required — `build.sh` compiles directly with `swiftc` and assembles the `.app` bundle. Requires Xcode or the Command Line Tools.

```bash
git clone https://github.com/beutton/wattsec.git
cd wattsec
./build.sh
open dist/WattSecPlus.app
```

By default the build targets your machine's native architecture (arm64 on Apple Silicon, x86_64 on Intel), which is faster and produces a smaller binary. To build a universal binary for distribution:

```bash
./build.sh --universal
```

Full options:

| Flag | Description |
|---|---|
| `-v, --version VERSION` | Override version (default: `VERSION` file) |
| `-u, --universal` | Build universal binary (arm64 + x86_64) |
| `-d, --create-dmg` | Package into a DMG |
| `-s, --sign ID` | Code sign with a Developer ID |
| `-k, --keychain PROFILE` | Keychain profile for notarization (used with `--sign`) |

## Settings

<p align="center">
<img src="https://github.com/user-attachments/assets/9d213036-225c-4369-9b18-1cb6b94956e1"/>
</p>

- **Detail** - The number of watt decimal places to show (0, 1, or 2)
- **Pace** - The refresh interval (1s, 3s, or 5s)
- **Width** - The width of the metric in the menu bar (Dynamic or Fixed)
- **Launch** - Toggle Launch at Login

## Credit

- [WattSec](https://github.com/beutton/wattsec) for the base WattSec app
- [Stats](https://github.com/exelban/stats) for SMC polling
