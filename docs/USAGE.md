# WattSec+ — Usage

## Menu bar

WattSec+ lives entirely in the menu bar. There is no Dock icon and no app switcher entry.

The default display shows wattage, battery (if enabled), and uptime in a single combined item. Click the item to open the menu.

### Menu bar item layout

In **grouped mode** (default), one item shows all enabled components in order:

```
[battery %] [wattage] [uptime]
```

For example: `84% 12.4w 3h 22m`

With the dash separator enabled: `84% - 12.4w - 3h 22m`

In **separated mode**, each component is an independent menu bar item you can Command-drag to reorder.

## Menu

Click any WattSec+ item in the menu bar to open the menu.

| Item | Description |
|---|---|
| **Detail** | Watt decimal places — Low (0), Medium (1), High (2) |
| **Pace** | Update interval — 1s, 3s, 5s |
| **Settings…** | Opens the settings window |
| **Quit WattSec+** | Exits the app |

## Settings window

Open via the menu → **Settings…**, or press Escape to close it.

The **Preview** at the top shows exactly what your menu bar item will look like with the current settings, updating live as the wattage changes.

### Wattage

**Detail** controls how many decimal places to show: Low = `12w`, Medium = `12.4w`, High = `12.38w`.

**Pace** sets how often the SMC is polled: 1s (fast), 3s (medium), 5s (slow). Lower pace = more responsive, slightly more CPU.

**Bar Width** in Fixed mode pre-calculates the width of the widest possible wattage string and holds it for 60 seconds after the value drops — prevents the menu bar from shifting when wattage crosses 100W.

### Appearance

**Font Size** has five steps — XS (10pt), S (12pt), M (12.5pt), L (13pt), XL (15pt).

**Labels** controls unit capitalisation: Lowercase = `12.4w  84%  3h 22m`, Uppercase = `12.4W  84%  3H 22M`.

### Menu Bar

**Show Battery** adds a battery percentage reading. When charging, an orange dot appears before the number. When plugged in but fully charged, a faint white dot appears instead. Battery state updates immediately on plug/unplug without waiting for the next SMC poll.

**Show Uptime** adds system uptime (time since last boot). Sub-options appear when this is on:

- **Compact format** — removes spaces: `3h22m` instead of `3h 22m`
- **Always show minutes** — includes minutes even when the uptime spans multiple days (default shows only days + hours when ≥ 1 day)

### Layout

**Group into one item** (default on) shows all components in a single menu bar item. Turn this off to get three independent items you can Command-drag to any position in your menu bar.

**Show dash separator** uses ` - ` between components instead of a space: `84% - 12.4w - 3h 22m`.

### System

**Launch at Login** uses macOS's SMAppService to start WattSec+ automatically when you log in. This stores the preference in macOS's login items system, not in UserDefaults.

## Reordering menu bar items

In **separated mode** (Group into one item off), hold Command and drag any of the three WattSec+ items to reorder them relative to each other and other menu bar icons.

In grouped mode, Command-drag the single item to reorder it among other apps' menu bar icons.

## Removing menu bar items

If you Command-drag all WattSec+ items off the menu bar, the app will automatically quit after a few seconds. Relaunch it from `/Applications` to restore the items.

## Quitting

Click any WattSec+ item → **Quit WattSec+**.
