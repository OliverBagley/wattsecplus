# WattSec+ — Claude Context

Lightweight macOS menu bar app displaying real-time power consumption (wattage), battery percentage, charge status, and system uptime. Fork of [beutton/wattsec](https://github.com/beutton/wattsec). Goal is minimal resource impact and clean display.

---

## Project Structure

```
wattsecplus/
├── WattSec/
│   ├── main.swift             # AppKit bootstrap (entry point)
│   ├── WattSecApp.swift       # All app logic — AppDelegate + PowerMonitor
│   ├── SMC.swift              # IOKit SMC interface (reads PSTR key for wattage)
│   ├── Info.plist             # Source plist — __VERSION__ substituted at build time
│   ├── WattSec.entitlements   # Sandbox disabled; login items + automation enabled
│   └── Assets.xcassets/       # App icon (used by build.sh to generate AppIcon.icns)
├── build.sh                   # Pure swiftc build — no Xcode project required
├── VERSION                    # Single-line version string read by build.sh
├── README.md
└── CLAUDE.md                  # This file
```

No `.xcodeproj`. No SwiftUI. Build and run entirely via `build.sh`.

---

## Build System

**No Xcode project.** `build.sh` compiles with `swiftc` directly and assembles the `.app` bundle manually. Requires Xcode or Command Line Tools.

```bash
./build.sh                # native arch (arm64 on Apple Silicon) — fast, small
./build.sh --universal    # arm64 + x86_64 via lipo — for distribution only
./build.sh -d             # also package a DMG
./build.sh -s "Developer ID" -k "KeychainProfile" -d  # sign + notarise + DMG
```

Version comes from the `VERSION` file. Update that file to bump the version — no other changes needed. The build script substitutes `__VERSION__` in `Info.plist` at build time via `sed`.

The build produces `dist/WattSecPlus.app`. The `dist/` directory is gitignored and fully regenerated on each build.

---

## Architecture

### Entry Point — `main.swift`
Minimal AppKit bootstrap: `NSApplication.shared` → `AppDelegate()` → `app.run()`. `LSUIElement: true` in `Info.plist` keeps the app out of the Dock and app switcher.

### `AppDelegate` (in `WattSecApp.swift`)
The entire application lives here. Key responsibilities:

- **Status items** — up to three `NSStatusItem`s: wattage (primary, always present), battery (optional), uptime (optional). All three are independent so the user can Command-drag to reorder them. In grouped mode, a single combined attributed string is rendered in the wattage item and the other two are removed from the status bar entirely.
- **Menu** — hosted on the wattage item's button. All settings are toggled/selected via this menu.
- **Display pipeline** — `PowerMonitor.$wattage` is observed via a debounced Combine sink (0.1s). Every wattage change calls `updateWattageDisplay()` which builds attributed strings and sets them on the status item buttons.
- **Battery cache** — `refreshBatteryCache()` reads IOKit once at launch and again only when `IOPSNotificationCreateRunLoopSource` fires (plug/unplug events). `batteryAttributedString()` reads from `cachedBattery` — no IOKit calls on the render path.
- **Font cache** — `_cachedFont` and `_cachedDotImages` are invalidated only when the user changes font size. `currentFont()` returns the cached instance; never allocates on the hot path.
- **Status item watcher** — a 4-second timer checks whether all status item buttons have lost their windows (user Command-dragged all items off). If so, the app terminates so a relaunch recreates them.

### `PowerMonitor` (in `WattSecApp.swift`)
Singleton. Uses a `DispatchSourceTimer` on a dedicated `.utility` queue (`com.oliverbagley.WattSecPlus.smc`) — no Combine Timer, no main-thread polling. On each tick it calls `SMC.shared.getValue("PSTR")`, clamps the result to `max(0.0, raw)` (SMC can return small negatives during charge handoffs), and posts `wattage` + `lastReadFailed` back to the main thread. When `lastReadFailed` is true the display shows `—` instead of a number.

Pace options: 1s (fast), 3s (medium), 5s (slow). Timer is rebuilt on pace change; guard prevents redundant rebuilds.

### `SMC.swift`
Thin IOKit wrapper. Opens a connection to `AppleSMC` on init (private singleton init — prevents accidental second connections). `getValue(_ key: String) -> Double?` sends two IOKit calls: `readKeyInfo` then `readBytes`. Reads the `flt ` (4-byte float) data type and converts to Double. Only key used is `"PSTR"` (system power draw in watts).

---

## User-Facing Settings (UserDefaults keys)

| Key | Type | Default | Description |
|---|---|---|---|
| `detailLevel` | Int | 1 (medium) | Watt decimal places: 0 / 1 / 2 |
| `paceLevel` | Int | 1 (fast) | Update interval in seconds: 1 / 3 / 5 |
| `widthMode` | String | "dynamic" | "dynamic" or "fixed" menu bar width |
| `fontSize` | Int | 2 (medium) | Font size index 0–4 (10–15pt) |
| `labelCase` | String | "lowercase" | "uppercase" or "lowercase" units/labels |
| `showUptime` | Bool | true | Show uptime in menu bar |
| `uptimeCompact` | Bool | false | Remove spaces between uptime components |
| `uptimeShowMinutes` | Bool | false | Always show minutes even when showing days |
| `showBattery` | Bool | false | Show battery percentage in menu bar |
| `showDash` | Bool | false | Use " - " separator between grouped components |
| `groupStatusItems` | Bool | true | Single combined item vs. three separate items |

Settings version key: `settingsVersion` (currently `1`). Bump this in `loadUserPreferences()` to force a reset to defaults on next launch.

Launch at login is managed via `SMAppService.mainApp` — not stored in UserDefaults.

---

## Display Logic

### Grouped mode (default)
One `NSStatusItem`. Combined attributed string order: **Battery · Wattage · Uptime**. Separator between components is `" "` (default), `" - "` (showDash), or `""` (uptimeCompact). Secondary status items are removed from the status bar (avoids ghost slots).

### Separated mode
Three independent `NSStatusItem`s created on-demand. User can Command-drag to reorder. Battery and uptime items are hidden (not removed) when their respective toggles are off.

### Fixed width mode
Pre-calculates the pixel width of the widest possible string at the current font size for each detail level. Switches to the wider slot when wattage crosses 100W, then holds it for 60 seconds after dropping back below (avoids rapid width jitter). Recalculated when font size changes.

### Attributed string rendering
- Wattage: number at full font size, `w`/`W` unit at 70% size.
- Battery: optional coloured dot (orange = charging, white 70% opacity = plugged idle) + number at full size + `%` at 70% size in lowercase mode.
- Uptime: numbers at full size, unit labels (`d`/`h`/`m`) at 75% size. Components computed by `uptimeComponents()` via `sysctl(KERN_BOOTTIME)` with `ProcessInfo.processInfo.systemUptime` as fallback.

---

## Key Design Decisions & Constraints

- **No SwiftUI** — removed entirely. Entry point is `main.swift` + `AppDelegate`. SwiftUI framework is never loaded.
- **No Xcode project** — `build.sh` + `swiftc` only. Do not add an `.xcodeproj`.
- **Minimal footprint** — every optimisation decision prioritises CPU/memory impact. No polling where event-driven is possible (IOKit notifications for battery, DispatchSourceTimer not RunLoop timer for SMC).
- **Combine kept for `@Published`** — `PowerMonitor` uses `@Published`/`ObservableObject` for the Combine subscription in `AppDelegate`. Combine is part of the standard library overlay and adds no significant overhead.
- **App Sandbox disabled** — required for IOKit SMC access. Entitlement `com.apple.security.app-sandbox` is `false`. This means the app cannot be distributed via the Mac App Store.
- **Minimum deployment target: macOS 13.0** — set in `Info.plist` and all `swiftc -target` flags. `SMAppService` (login items) requires 13.0+.

---

## Things to Be Careful About

- `SMC.shared` is a private-init singleton backed by a persistent `io_connect_t`. Never create a second `SMC()` instance — it would open a duplicate IOKit connection.
- `updateMenuStates(_:selectedValue:)` uses a typed `switch` to compare `Int` vs `Int` and `String` vs `String`. Do not revert to `===` identity comparison — it breaks checkmarks for String-keyed settings (WidthMode, LabelCase).
- `_cachedFont` and `_cachedDotImages` must both be invalidated together in `changeFontSize(_:)` — dot diameter is font-relative.
- `groupStatusItems` mode removes secondary `NSStatusItem`s from the status bar entirely (not just hides them). Re-entering separated mode recreates them. This is intentional to avoid ghost/empty slots.
- The status item watcher timer fires on the main run loop — do not add `DispatchQueue.main.async` inside its callback.
- `PowerMonitor.readAndPublish()` runs on `smcQueue` (background). Always dispatch back to main before touching `@Published` properties.
