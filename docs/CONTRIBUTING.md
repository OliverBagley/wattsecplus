# WattSec+ — Contributing

## Build system

No Xcode project. Everything compiles via `build.sh` using `swiftc` directly. To add a new Swift source file, append it to the `src_files` array in `build.sh`:

```bash
src_files=(
    WattSec/main.swift
    WattSec/SMC.swift
    WattSec/WattSecApp.swift
    WattSec/SettingsWindow.swift
    WattSec/YourNewFile.swift   # add here
)
```

Test your change with a native build:

```bash
./build.sh && open dist/WattSecPlus.app
```

## Architecture

The full architecture reference is in [CLAUDE.md](../CLAUDE.md) and [llms-full.txt](../llms-full.txt). Key points:

**No SwiftUI.** Entry point is `main.swift` + `NSApplicationDelegate`. Never import SwiftUI or use the `@main` attribute.

**No Xcode project.** Do not add a `.xcodeproj`. All compilation is via `build.sh`.

**Minimal footprint.** Every design decision prioritises CPU and memory impact. Prefer event-driven updates (IOKit notifications) over polling wherever possible.

## Adding a new setting

1. **Add a UserDefaults key** — choose a descriptive camelCase string, e.g. `"showTemperature"`.

2. **Add an in-memory property** to `AppDelegate` in `WattSecApp.swift`:
   ```swift
   private var showTemperature: Bool = false
   ```

3. **Register a default** in `loadUserPreferences()`:
   ```swift
   defaults.register(defaults: [
       // existing entries...
       "showTemperature": false,
   ])
   ```

4. **Read the value** from UserDefaults in `loadUserPreferences()`:
   ```swift
   showTemperature = defaults.bool(forKey: "showTemperature")
   ```

5. **Handle the change** in `applyChange(forKey:)`:
   ```swift
   case "showTemperature":
       showTemperature = defaults.bool(forKey: "showTemperature")
       updateWattageDisplay()
   ```

6. **Add a control** in `SettingsWindow.swift` — checkbox, segmented control, or similar. Write the new value to UserDefaults in the action handler, then call `appDelegate?.applyChange(forKey: "showTemperature")`.

7. **Sync the control** in `SettingsWindowController.syncControls()` so it reflects the current value when the window opens.

8. **Document the key** in the UserDefaults schema table in `CLAUDE.md` and `llms-full.txt`.

## Modifying the display

Display rendering happens in `updateWattageDisplay()` and its helpers in `WattSecApp.swift`. The full grouped attributed string is produced by `buildMenuBarAttributedString()` — this is also called by `SettingsWindow` for the live preview, so any change here is reflected in both places.

Font and dot image caches (`_cachedFont`, `_cachedDotImages`) must be invalidated together — both are font-size-relative. Always invalidate both in `changeFontSize(_:)`.

## Modifying the settings window

The settings window is entirely programmatic in `SettingsWindow.swift`. Layout uses `NSStackView` with `GlassCardView` section cards. Add new rows with `makeRow(_:_:)` (labelled control) or `makeCheckRow(_:indent:)` (checkbox).

Window height is fixed at 730pt in the `convenience init`. If you add or remove sections, adjust this value to fit.

## Code style

- Swift standard library types wherever possible; no third-party dependencies
- `private` by default — only expose what SettingsWindow or tests genuinely need
- Force-unwraps only where the value is guaranteed by the initialisation path (e.g. `window!` inside `showWindow`)
- Separate `// MARK: -` sections for logical groups within a file
- No trailing whitespace; 4-space indentation

## SMC access

Never create a second `SMC()` instance. `SMC.shared` holds a persistent `io_connect_t` to `AppleSMC`. A second connection would either fail silently or cause undefined behaviour with the driver.

If you need to read additional SMC keys, add them as methods on the existing `SMC` singleton rather than opening a new connection.

## Deployment target

macOS 13.0 is the minimum. Do not use APIs introduced after 13.0 without a `@available` guard. `SMAppService` is 13.0+, which is already the floor. Key new API used: `SMAppService.mainApp` for Login Items.

## Versioning

The version string lives in the `VERSION` file (e.g. `2025.03.05`). Update this file — no other changes needed. The build script substitutes `__VERSION__` in `Info.plist` automatically via `sed`.

## Testing

There is no automated test suite. Verify changes by building and running:

```bash
./build.sh && open dist/WattSecPlus.app
```

Manual checklist for any display change:
- [ ] Grouped mode shows correct string
- [ ] Separated mode updates each item independently
- [ ] Settings window preview matches the actual menu bar
- [ ] Font size changes take immediate effect
- [ ] Dark mode and light mode both render correctly
- [ ] Plug/unplug updates battery indicator without waiting for next SMC poll
