# WattSec+ — Setup

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode **or** the Command Line Tools:

```bash
xcode-select --install
```

Full Xcode is recommended. The Command Line Tools work but some SDK paths may differ — the build script will warn you if CLT is the active toolchain.

For DMG packaging you also need [create-dmg](https://github.com/create-dmg/create-dmg):

```bash
brew install create-dmg
```

## Build

```bash
git clone https://github.com/oliverbagley/wattsecplus.git
cd wattsecplus
./build.sh
```

The build produces `dist/WattSecPlus.app`. Open it directly or move it to `/Applications`.

```bash
open dist/WattSecPlus.app
```

## Build options

| Flag | Description |
|---|---|
| `-v VERSION` | Override version string (default: `VERSION` file) |
| `-u, --universal` | Build universal binary (arm64 + x86_64) via lipo |
| `-d, --create-dmg` | Package into a DMG after building |
| `-s "Developer ID..."` | Code sign with the given Developer ID Application certificate |
| `-k "KeychainProfile"` | Keychain profile for notarytool (required with `--sign`) |

### Native build (default)

Targets your machine's architecture only. Fastest and smallest:

```bash
./build.sh
```

### Universal build for distribution

Compiles arm64 and x86_64 separately then merges with `lipo`:

```bash
./build.sh --universal
```

### Signed DMG for distribution

```bash
./build.sh --universal --sign "Developer ID Application: Your Name (TEAMID)" \
           --keychain "your-notarytool-profile" --create-dmg
```

## Updating the version

Edit the `VERSION` file — no other changes needed. The build script substitutes `__VERSION__` in `Info.plist` automatically.

## Rebuilding

If `dist/` already exists, the script will ask before deleting it. Answer `y` or press Enter to proceed.

## Running without installing

```bash
./build.sh && open dist/WattSecPlus.app
```

The app appears in the menu bar immediately. To quit, use the menu bar menu → **Quit WattSec+**.
