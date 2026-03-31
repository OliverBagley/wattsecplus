//
//  WattSecApp.swift
//  WattSec+
//
//  Created by Ben Beutton on 3/4/25.
//

import Cocoa
import Combine
import Foundation
import Darwin
import ServiceManagement
import IOKit.ps
import SwiftUI

// MARK: - Main App

@main
struct WattSecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Enums

enum DetailLevel: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
}

enum PaceLevel: Int, CaseIterable {
    case fast = 1
    case medium = 3
    case slow = 5
}

enum WidthMode: String, CaseIterable {
    case dynamic
    case fixed
}

enum LabelCase: String, CaseIterable {
    case uppercase
    case lowercase
}

enum FontSize: Int, CaseIterable {
    case extraSmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case extraLarge = 4

    var pointSize: CGFloat {
        switch self {
        case .extraSmall: return 10
        case .small:      return 12
        case .medium:     return 12.5
        case .large:      return 13
        case .extraLarge: return 15
        }
    }

    var label: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small:      return "Small"
        case .medium:     return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}

// MARK: Default Settings

private struct Defaults {
    static let detailLevel: DetailLevel = .medium
    static let paceLevel: PaceLevel = .fast
    static let widthMode: WidthMode = .dynamic
    static let fontSize: FontSize = .medium
    static let labelCase: LabelCase = .lowercase
    static let showUptime: Bool = true
    static let uptimeCompact: Bool = false
    static let uptimeShowMinutes: Bool = false
    static let showBattery: Bool = false
    static let showDash: Bool = false
}

// MARK: Constants

private struct Constants {
    static let highWattageTimeoutSeconds: TimeInterval = 60.0
    static let highWattageThreshold: Double = 100.0
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Properties
    
    private var statusItem: NSStatusItem?
    // Separate status items so the user can reorder them with Command-drag
    private var statusItemWattage: NSStatusItem?
    private var statusItemBattery: NSStatusItem?
    private var statusItemUptime: NSStatusItem?
    private var wattageSubscription: AnyCancellable?
    
    private var detailLevel: DetailLevel = Defaults.detailLevel
    private var paceLevel: PaceLevel = Defaults.paceLevel
    private var widthMode: WidthMode = Defaults.widthMode
    private var launchAtLogin: Bool = false
    private var showUptime: Bool = false
    private var fontSize: FontSize = Defaults.fontSize
    private var labelCase: LabelCase = Defaults.labelCase
    private var uptimeCompact: Bool = Defaults.uptimeCompact
    private var uptimeShowMinutes: Bool = Defaults.uptimeShowMinutes
    private var showBattery: Bool = Defaults.showBattery
    private var showDash: Bool = Defaults.showDash
    private var groupStatusItems: Bool = true
    
    
    // New properties for fixed width mode
    private var widestWidths: [DetailLevel: [Int: CGFloat]] = [:]
    private var highWattageTimestamp: Date?
    private var highWattageTimer: Timer?
    // RunLoop source for IOKit power-source change notifications
    private var powerSourceRunLoopSource: CFRunLoopSource?
    
    // MARK: Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        loadUserPreferences()
        setupMenuBar()
        calculateWidestWidths()
        bindToPowerMonitor()
        PowerMonitor.shared.fetchWattage()
        checkLaunchAtLoginStatus()
        // Register for power-source change notifications so battery UI updates immediately
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let src = IOPSNotificationCreateRunLoopSource({ context in
            if let ctx = context {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.powerSourceChanged()
                }
            }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, CFRunLoopMode.defaultMode)
            powerSourceRunLoopSource = src
        }
    }
    
    deinit {
        // Cancel subscription to prevent memory leaks
        wattageSubscription?.cancel()
        highWattageTimer?.invalidate()
        if let src = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, CFRunLoopMode.defaultMode)
            powerSourceRunLoopSource = nil
        }
    }

    private func powerSourceChanged() {
        // Called when the system power sources change (plug/unplug). Refresh display.
        updateWattageDisplay()
    }
    
    // MARK: User Preferences
    
    private func loadUserPreferences() {
        let defaults = UserDefaults.standard

        // Register factory defaults — only applied when a key has never been set
        defaults.register(defaults: [
            "detailLevel": Defaults.detailLevel.rawValue,
            "paceLevel":   Defaults.paceLevel.rawValue,
            "widthMode":   Defaults.widthMode.rawValue,
            "fontSize":    Defaults.fontSize.rawValue,
            "labelCase":   Defaults.labelCase.rawValue,
            "showUptime":  Defaults.showUptime,
            "uptimeCompact": Defaults.uptimeCompact,
            "uptimeShowMinutes": Defaults.uptimeShowMinutes,
            "showBattery": Defaults.showBattery,
            "showDash": Defaults.showDash,
            "groupStatusItems": true
        ])

        let currentVersion = 1
        let savedVersion = defaults.integer(forKey: "settingsVersion")
        
        if savedVersion < currentVersion {
            // Reset to defaults if version is outdated, then update version
            defaults.set(currentVersion, forKey: "settingsVersion")
            defaults.set(Defaults.detailLevel.rawValue, forKey: "detailLevel")
            defaults.set(Defaults.paceLevel.rawValue, forKey: "paceLevel")
            defaults.set(Defaults.widthMode.rawValue, forKey: "widthMode")
            // We don't need to set launchAtLogin in UserDefaults anymore
        }
        
        detailLevel = DetailLevel(rawValue: defaults.integer(forKey: "detailLevel")) ?? Defaults.detailLevel
        paceLevel = PaceLevel(rawValue: defaults.integer(forKey: "paceLevel")) ?? Defaults.paceLevel
        widthMode = WidthMode(rawValue: defaults.string(forKey: "widthMode") ?? Defaults.widthMode.rawValue) ?? Defaults.widthMode
        showUptime = defaults.bool(forKey: "showUptime")
        fontSize = FontSize(rawValue: defaults.integer(forKey: "fontSize")) ?? Defaults.fontSize
        labelCase = LabelCase(rawValue: defaults.string(forKey: "labelCase") ?? Defaults.labelCase.rawValue) ?? Defaults.labelCase
        uptimeCompact = defaults.bool(forKey: "uptimeCompact")
        uptimeShowMinutes = defaults.bool(forKey: "uptimeShowMinutes")
        showBattery = defaults.bool(forKey: "showBattery")
        showDash = defaults.bool(forKey: "showDash")
        groupStatusItems = defaults.bool(forKey: "groupStatusItems")
        
        
        // We'll set launchAtLogin in checkLaunchAtLoginStatus() instead
        
        PowerMonitor.shared.updatePace(paceLevel)
    }
    
    // MARK: Widest Width Calculation
    
    private func calculateWidestWidths() {
        // Widest strings for each detail level and character count
        let widestStrings: [DetailLevel: [Int: String]] = [
            .low: [
                3: "20W",    // 3 chars
                4: "344W"    // 4 chars
            ],
            .medium: [
                5: "44.4W",  // 5 chars
                6: "304.4W"  // 6 chars
            ],
            .high: [
                6: "30.44W", // 6 chars
                7: "204.44W" // 7 chars
            ]
        ]
        
        // Calculate widths for widest strings
        for (level, strings) in widestStrings {
            widestWidths[level] = [:]
            for (charCount, widestString) in strings {
                let width = ceil(estimateTextWidth(widestString, font: currentFont())) + 1
                widestWidths[level]?[charCount] = width
            }
        }
    }
    
    // MARK: Menu Setup
    
    private func setupMenuBar() {
        // Create three status items so the user can reorder them independently
        statusItemWattage = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItemBattery = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItemUptime = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let wattButton = statusItemWattage?.button,
              let battButton = statusItemBattery?.button,
              let upButton = statusItemUptime?.button else {
            print("Failed to create status items. Terminating app.")
            NSApplication.shared.terminate(self)
            return
        }

        // All buttons open the same menu; wattage item hosts the menu object
        wattButton.action = #selector(showMenu)
        wattButton.target = self
        battButton.action = #selector(showMenu)
        battButton.target = self
        upButton.action = #selector(showMenu)
        upButton.target = self

        let menu = NSMenu()
        menu.addItem(createDetailMenuItem())
        menu.addItem(createPaceMenuItem())
        menu.addItem(createWidthModeItem())
        menu.addItem(createFontSizeMenuItem())
        menu.addItem(createLabelCaseMenuItem())
        menu.addItem(createGroupingMenuItem())
        menu.addItem(createShowDashMenuItem())
        // Battery toggle as a top-level menu item
        menu.addItem(createBatteryMenuItem())
        menu.addItem(createUptimeMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(createLaunchAtLoginMenuItem())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItemWattage?.menu = menu
    }
    
    private func createDetailMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Detail", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        for level in DetailLevel.allCases {
            let label = String(describing: level).capitalized
            let item = createStyledMenuItem(
                title: label,
                suffix: "\(level.rawValue)",
                action: #selector(changeDetailLevel),
                value: level.rawValue,
                isSelected: level == detailLevel
            )
            submenu.addItem(item)
        }
        
        menuItem.submenu = submenu
        return menuItem
    }
    
    private func createPaceMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Pace", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        for level in PaceLevel.allCases {
            let label = String(describing: level).capitalized
            let item = createStyledMenuItem(
                title: label,
                suffix: "\(level.rawValue)s",
                action: #selector(changePace),
                value: level.rawValue,
                isSelected: level == paceLevel
            )
            submenu.addItem(item)
        }
        
        menuItem.submenu = submenu
        return menuItem
    }
    
    private func createWidthModeItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Width", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        for mode in WidthMode.allCases {
            let label = mode == .dynamic ? "Dynamic" : "Fixed"
            let item = NSMenuItem(title: label, action: #selector(changeWidthMode), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            item.state = mode == widthMode ? .on : .off
            submenu.addItem(item)
        }
        
        menuItem.submenu = submenu
        return menuItem
    }
    
    private func createFontSizeMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for size in FontSize.allCases {
            let item = createStyledMenuItem(
                title: size.label,
                suffix: "\(size.pointSize)pt",
                action: #selector(changeFontSize),
                value: size.rawValue,
                isSelected: size == fontSize
            )
            submenu.addItem(item)
        }

        menuItem.submenu = submenu
        return menuItem
    }

    private func createLabelCaseMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Case", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for mode in LabelCase.allCases {
            let label = mode == .uppercase ? "Uppercase" : "Lowercase"
            let item = NSMenuItem(title: label, action: #selector(changeLabelCase), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            item.state = mode == labelCase ? .on : .off
            submenu.addItem(item)
        }

        menuItem.submenu = submenu
        return menuItem
    }

    private func createUptimeMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Uptime", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let item = NSMenuItem(title: "Show in Menubar", action: #selector(toggleShowUptime), keyEquivalent: "")
        item.target = self
        item.state = showUptime ? .on : .off
        submenu.addItem(item)

        let compactItem = NSMenuItem(title: "Compact Uptime", action: #selector(toggleCompactUptime), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = uptimeCompact ? .on : .off
        submenu.addItem(compactItem)

        let showMinutesItem = NSMenuItem(title: "Always Show Minutes", action: #selector(toggleShowMinutes), keyEquivalent: "")
        showMinutesItem.target = self
        showMinutesItem.state = uptimeShowMinutes ? .on : .off
        submenu.addItem(showMinutesItem)

        // Battery toggle moved to top-level menu

        let separator = NSMenuItem.separator()
        submenu.addItem(separator)

        menuItem.submenu = submenu
        return menuItem
    }

    private func createBatteryMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Show Battery", action: #selector(toggleShowBattery), keyEquivalent: "")
        item.target = self
        item.state = showBattery ? .on : .off
        return item
    }

    private func createLaunchAtLoginMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Launch", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let item = NSMenuItem(title: "at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        item.state = launchAtLogin ? .on : .off
        submenu.addItem(item)
        
        menuItem.submenu = submenu
        return menuItem
    }

    private func createGroupingMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Group Items", action: #selector(toggleGroupItems), keyEquivalent: "")
        item.target = self
        item.state = groupStatusItems ? .on : .off
        return item
    }

    private func createShowDashMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Show Dash", action: #selector(toggleShowDash), keyEquivalent: "")
        item.target = self
        item.state = showDash ? .on : .off
        return item
    }

    @objc private func toggleShowDash(sender: NSMenuItem) {
        showDash = !showDash
        UserDefaults.standard.set(showDash, forKey: "showDash")
        sender.state = showDash ? .on : .off
        updateWattageDisplay()
    }

    @objc private func toggleGroupItems(sender: NSMenuItem) {
        groupStatusItems = !groupStatusItems
        UserDefaults.standard.set(groupStatusItems, forKey: "groupStatusItems")
        sender.state = groupStatusItems ? .on : .off
        updateWattageDisplay()
    }

    // spacingPx removed; single-space (or dash) separators used instead
    
    // MARK: Menu Actions
    
    @objc private func changeDetailLevel(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let newLevel = DetailLevel(rawValue: rawValue) else { return }
        
        detailLevel = newLevel
        UserDefaults.standard.set(rawValue, forKey: "detailLevel")
        updateWattageDisplay()
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }
    
    @objc private func changePace(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let newPace = PaceLevel(rawValue: rawValue) else { return }
        
        paceLevel = newPace
        UserDefaults.standard.set(rawValue, forKey: "paceLevel")
        PowerMonitor.shared.updatePace(newPace)
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }
    
    @objc private func changeWidthMode(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let newMode = WidthMode(rawValue: rawValue) else { return }
        
        widthMode = newMode
        UserDefaults.standard.set(rawValue, forKey: "widthMode")
        
        switch newMode {
        case .dynamic:
            statusItem?.length = NSStatusItem.variableLength
            highWattageTimer?.invalidate()
            highWattageTimer = nil
            highWattageTimestamp = nil
        case .fixed:
            // Initialize widest widths if needed
            if widestWidths.isEmpty {
                calculateWidestWidths()
            }
        }
        
        updateWattageDisplay()
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }
    
    @objc private func changeFontSize(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let newSize = FontSize(rawValue: rawValue) else { return }

        fontSize = newSize
        UserDefaults.standard.set(rawValue, forKey: "fontSize")
        calculateWidestWidths()
        updateWattageDisplay()
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }

    @objc private func changeLabelCase(sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let newCase = LabelCase(rawValue: rawValue) else { return }

        labelCase = newCase
        UserDefaults.standard.set(rawValue, forKey: "labelCase")
        updateWattageDisplay()
        updateMenuStates(sender.menu, selectedValue: rawValue)
    }

    @objc private func toggleShowUptime(sender: NSMenuItem) {
        showUptime = !showUptime
        UserDefaults.standard.set(showUptime, forKey: "showUptime")
        sender.state = showUptime ? .on : .off
        updateWattageDisplay()
    }

    @objc private func toggleCompactUptime(sender: NSMenuItem) {
        // When compact is ON we remove the space between components.
        uptimeCompact = !uptimeCompact
        UserDefaults.standard.set(uptimeCompact, forKey: "uptimeCompact")
        sender.state = uptimeCompact ? .on : .off
        updateWattageDisplay()
    }

    @objc private func toggleShowMinutes(sender: NSMenuItem) {
        // When enabled, always show minutes even when days are displayed
        uptimeShowMinutes = !uptimeShowMinutes
        UserDefaults.standard.set(uptimeShowMinutes, forKey: "uptimeShowMinutes")
        sender.state = uptimeShowMinutes ? .on : .off
        updateWattageDisplay()
    }

    @objc private func toggleShowBattery(sender: NSMenuItem) {
        showBattery = !showBattery
        UserDefaults.standard.set(showBattery, forKey: "showBattery")
        sender.state = showBattery ? .on : .off
        updateWattageDisplay()
    }

    // MARK: Display Updates
    
    private func currentFont() -> NSFont {
        return NSFont.systemFont(ofSize: fontSize.pointSize)
    }

    private func wattageAttributedString(from wattageText: String) -> NSAttributedString {
        let baseFont = currentFont()
        let attrs: [NSAttributedString.Key: Any] = [.font: baseFont]
        // If the last character is a unit ('w' or 'W'), render it smaller
        guard let last = wattageText.last else {
            return NSAttributedString(string: wattageText, attributes: attrs)
        }

        let unitChars: Set<Character> = ["w", "W"]
        if unitChars.contains(last) {
            let numberPart = String(wattageText.dropLast())
            let smallFont = NSFont.systemFont(ofSize: baseFont.pointSize * 0.7)
            let smallAttrs: [NSAttributedString.Key: Any] = [.font: smallFont]

            let out = NSMutableAttributedString()
            out.append(NSAttributedString(string: numberPart, attributes: attrs))
            out.append(NSAttributedString(string: String(last), attributes: smallAttrs))
            return out
        }

        return NSAttributedString(string: wattageText, attributes: attrs)
    }

    private func updateWattageDisplay() {
        let formatString = detailLevelFormatString()
        let wattage = PowerMonitor.shared.wattage
        let wattageText = String(format: formatString, wattage)

        let attrs: [NSAttributedString.Key: Any] = [.font: currentFont()]

        if groupStatusItems {
            // Build a single combined attributed string in the fixed order the user
            // requested: Battery percent (+charge icon), Wattage, Uptime.
            let result = NSMutableAttributedString()

            // Determine separator between major components. `showDash` takes
            // precedence; `uptimeCompact` removes separators entirely.
            let sep: String
            if uptimeCompact {
                sep = ""
            } else if showDash {
                sep = " - "
            } else {
                sep = " "
            }

            // 1) Battery (percent + optional charge icon)
            if showBattery, let bAttr = batteryAttributedString() {
                result.append(bAttr)
                // separator between battery and wattage
                result.append(NSAttributedString(string: sep, attributes: attrs))
            }

            // 2) Wattage
            let wattAttr = wattageAttributedString(from: wattageText)
            result.append(wattAttr)

            // spacer between wattage and uptime
            if showUptime {
                result.append(NSAttributedString(string: sep, attributes: attrs))
                result.append(uptimeAttributedString())
            }

            if let wBtn = statusItemWattage?.button {
                wBtn.attributedTitle = result
                wBtn.isHidden = false
            }

            // Hide the other status item buttons while grouped
            statusItemBattery?.button?.attributedTitle = NSAttributedString(string: "", attributes: attrs)
            statusItemBattery?.button?.isHidden = true
            statusItemUptime?.button?.attributedTitle = NSAttributedString(string: "", attributes: attrs)
            statusItemUptime?.button?.isHidden = true
        } else {
            // Separate items mode
            if let wBtn = statusItemWattage?.button {
                let wattAttr = wattageAttributedString(from: wattageText)
                wBtn.attributedTitle = wattAttr
                wBtn.isHidden = false
            }

            if let bBtn = statusItemBattery?.button {
                if showBattery, let bAttr = batteryAttributedString() {
                    // simple single-space spacer (system controls inter-item spacing)
                    let combined = NSMutableAttributedString(string: " ", attributes: attrs)
                    combined.append(bAttr)
                    bBtn.attributedTitle = combined
                    bBtn.isHidden = false
                } else {
                    bBtn.attributedTitle = NSAttributedString(string: "", attributes: attrs)
                    bBtn.isHidden = !showBattery
                }
            }

            if let uBtn = statusItemUptime?.button {
                if showUptime {
                    let upAttr = uptimeAttributedString()
                    uBtn.attributedTitle = upAttr
                    uBtn.isHidden = false
                } else {
                    uBtn.attributedTitle = NSAttributedString(string: "", attributes: attrs)
                    uBtn.isHidden = !showUptime
                }
            }
        }

        // Width adjustments apply to the wattage item (primary)
        if widthMode == .fixed && !showUptime {
            updateFixedWidth(for: wattageText, wattage: wattage)
        } else if showUptime {
            statusItemWattage?.length = NSStatusItem.variableLength
        }
    }

    private func uptimeString() -> String {
        // Prefer using kernel boottime (like the `uptime` command) for accuracy
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size

        let result = mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
            return sysctl(mibPtr.baseAddress, 2, &bootTime, &size, nil, 0)
        }

        let uptimeSeconds: Int
        if result == 0 {
            var now = time_t()
            time(&now)
            uptimeSeconds = Int(now - bootTime.tv_sec)
        } else {
            // Fallback if sysctl fails
            uptimeSeconds = Int(ProcessInfo.processInfo.systemUptime)
        }

        let totalMinutes = uptimeSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let days = hours / 24
        let remainingHours = hours % 24

        let up = labelCase == .uppercase
        let d = up ? "D" : "d"
        let h = up ? "H" : "h"
        let m = up ? "M" : "m"
        // Compact = no space; when compact is off we include a space
        let sep = uptimeCompact ? "" : " "

        if days > 0 {
            // When showing days, omit minutes unless user enabled Show Minutes
            if uptimeShowMinutes {
                return "\(days)\(d)\(sep)\(remainingHours)\(h)\(sep)\(minutes)\(m)"
            }
            return "\(days)\(d)\(sep)\(remainingHours)\(h)"
        } else if hours > 0 {
            return "\(hours)\(h)\(sep)\(minutes)\(m)"
        } else {
            return "\(minutes)\(m)"
        }
    }

    private func uptimeAttributedString() -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [.font: currentFont()]
        let smallFont = NSFont.systemFont(ofSize: currentFont().pointSize * 0.75)
        let smallAttrs: [NSAttributedString.Key: Any] = [.font: smallFont]

        // Compute raw components using uptimeString logic
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size

        let result = mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
            return sysctl(mibPtr.baseAddress, 2, &bootTime, &size, nil, 0)
        }

        let uptimeSeconds: Int
        if result == 0 {
            var now = time_t()
            time(&now)
            uptimeSeconds = Int(now - bootTime.tv_sec)
        } else {
            uptimeSeconds = Int(ProcessInfo.processInfo.systemUptime)
        }

        let totalMinutes = uptimeSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let days = hours / 24
        let remainingHours = hours % 24

        let up = labelCase == .uppercase
        let d = up ? "D" : "d"
        let h = up ? "H" : "h"
        let m = up ? "M" : "m"
        let sep = uptimeCompact ? "" : " "

        let out = NSMutableAttributedString()

        if days > 0 {
            // days
            out.append(NSAttributedString(string: "\(days)", attributes: attrs))
            out.append(NSAttributedString(string: d, attributes: smallAttrs))
            if !uptimeCompact {
                out.append(NSAttributedString(string: sep, attributes: attrs))
            }
            // hours
            out.append(NSAttributedString(string: "\(remainingHours)", attributes: attrs))
            out.append(NSAttributedString(string: h, attributes: smallAttrs))
            if uptimeShowMinutes {
                if !uptimeCompact { out.append(NSAttributedString(string: sep, attributes: attrs)) }
                out.append(NSAttributedString(string: "\(minutes)", attributes: attrs))
                out.append(NSAttributedString(string: m, attributes: smallAttrs))
            }
        } else if hours > 0 {
            out.append(NSAttributedString(string: "\(hours)", attributes: attrs))
            out.append(NSAttributedString(string: h, attributes: smallAttrs))
            if !uptimeCompact { out.append(NSAttributedString(string: sep, attributes: attrs)) }
            out.append(NSAttributedString(string: "\(minutes)", attributes: attrs))
            out.append(NSAttributedString(string: m, attributes: smallAttrs))
        } else {
            out.append(NSAttributedString(string: "\(minutes)", attributes: attrs))
            out.append(NSAttributedString(string: m, attributes: smallAttrs))
        }

        return out
    }

    private func batteryAttributedString() -> NSAttributedString? {
        // Native IOKit power source API
        let attrs: [NSAttributedString.Key: Any] = [.font: currentFont()]

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sourcesRef = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else { return nil }

        let sources = sourcesRef as NSArray
        if sources.count == 0 { return nil }

        // Prefer the first power source
        for ps in sources {
            let psRef = ps as CFTypeRef
            if let descRef = IOPSGetPowerSourceDescription(snapshot, psRef)?.takeUnretainedValue() as? [String: Any] {
                // Current capacity may be provided as either a percent or as current/max
                var pctText: String? = nil
                if let cur = descRef[kIOPSCurrentCapacityKey as String] as? Int,
                   let max = descRef[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                    let pct = Int(round(Double(cur) / Double(max) * 100.0))
                    pctText = "\(pct)%"
                } else if let cur = descRef[kIOPSCurrentCapacityKey as String] as? Int {
                    pctText = "\(cur)%"
                }

                // Charging detection
                var isCharging = false
                if let charging = descRef[kIOPSIsChargingKey as String] as? Bool {
                    isCharging = charging
                } else if let state = descRef[kIOPSPowerSourceStateKey as String] as? String {
                    isCharging = (state == kIOPSACPowerValue as String)
                }

                if let pct = pctText {
                    let result = NSMutableAttributedString()

                    // Determine dot state: none (unplugged), charging (orange), plugged idle (white with opacity)
                    var showDot = false
                    var dotColor: NSColor = .clear
                    if isCharging {
                        showDot = true
                        dotColor = NSColor.systemOrange
                    } else if let state = descRef[kIOPSPowerSourceStateKey as String] as? String,
                              state == kIOPSACPowerValue as String {
                        // Plugged in but not charging
                        showDot = true
                        dotColor = NSColor.white.withAlphaComponent(0.7)
                    }

                    if showDot {
                        let dotDiameter = max(1.0, currentFont().pointSize * 0.45)
                        let dotImage = NSImage(size: NSSize(width: dotDiameter, height: dotDiameter), flipped: false) { rect in
                            dotColor.setFill()
                            let path = NSBezierPath(ovalIn: rect)
                            path.fill()
                            return true
                        }
                        let attachment = NSTextAttachment()
                        attachment.image = dotImage
                        // Center the dot vertically relative to the font cap height
                        let yOffset = (currentFont().capHeight - dotDiameter) / 2.0
                        attachment.bounds = CGRect(x: 0, y: yOffset, width: dotDiameter, height: dotDiameter)
                        result.append(NSAttributedString(attachment: attachment))
                        // small spacer after dot
                        result.append(NSAttributedString(string: " ", attributes: attrs))
                    }

                    // Split number and % so we can render '%' smaller in lowercase mode
                    let numberPart: String
                    let percentPart: String?
                    if pct.hasSuffix("%") {
                        numberPart = String(pct.dropLast())
                        percentPart = "%"
                    } else {
                        numberPart = pct
                        percentPart = nil
                    }

                    // Main number uses the current font
                    let numberAttr = NSAttributedString(string: numberPart, attributes: attrs)
                    result.append(numberAttr)

                    // Percent sign smaller when lowercase mode is active
                    if let pctChar = percentPart {
                        let pctFont: NSFont = (labelCase == .lowercase) ? NSFont.systemFont(ofSize: currentFont().pointSize * 0.7) : currentFont()
                        let pctAttrs: [NSAttributedString.Key: Any] = [.font: pctFont]
                        let pctAttr = NSAttributedString(string: pctChar, attributes: pctAttrs)
                        result.append(pctAttr)
                    }

                    return result
                }
            }
        }

        return nil
    }
    
    private func updateFixedWidth(for wattageText: String, wattage: Double) {
        let charCount = wattageText.count
        let isHighWattage = wattage >= Constants.highWattageThreshold
        
        guard let widthsForLevel = widestWidths[detailLevel],
              !widthsForLevel.isEmpty else {
            return
        }
        
        let sortedCharCounts = widthsForLevel.keys.sorted()
        let smallestCharCount = sortedCharCounts.first ?? 0
        let largestCharCount = sortedCharCounts.last ?? 0
        
        if isHighWattage {
            // For high wattage (≥100), use the largest width
            if highWattageTimestamp == nil {
                highWattageTimestamp = Date()
                if let width = widthsForLevel[largestCharCount] {
                    statusItemWattage?.length = width
                }
                
                // Cancel any existing timer
                highWattageTimer?.invalidate()
                highWattageTimer = nil
            }
        } else {
            // For lower wattage, determine appropriate width based on character count
            let targetCharCount = charCount <= smallestCharCount ? smallestCharCount : 
                                 (charCount >= largestCharCount ? largestCharCount : charCount)
            
            // If we were in high wattage mode, check if we should scale back
            if let timestamp = highWattageTimestamp {
                let timeInHighWattage = Date().timeIntervalSince(timestamp)
                
                if timeInHighWattage >= Constants.highWattageTimeoutSeconds {
                    // Scale back after timeout period
                    highWattageTimestamp = nil
                    if let width = widthsForLevel[targetCharCount] {
                        statusItem?.length = width
                    }
                    
                    // Cancel any existing timer
                    highWattageTimer?.invalidate()
                    highWattageTimer = nil
                } else if highWattageTimer == nil {
                    // Set a timer to check again after the remaining time
                    let remainingTime = Constants.highWattageTimeoutSeconds - timeInHighWattage
                    highWattageTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
                        self?.checkHighWattageTimeout()
                    }
                }
            } else {
                // Normal mode - use width based on character count
                if let width = widthsForLevel[targetCharCount] {
                    statusItemWattage?.length = width
                }
            }
        }
    }
    
    private func checkHighWattageTimeout() {
        guard let timestamp = highWattageTimestamp else {
            return
        }
        
        let timeInHighWattage = Date().timeIntervalSince(timestamp)
        if timeInHighWattage >= Constants.highWattageTimeoutSeconds && PowerMonitor.shared.wattage < Constants.highWattageThreshold {
            // Scale back after timeout period if wattage is still low
            highWattageTimestamp = nil
            
            // Update display with appropriate width
            updateWattageDisplay()
        }
        
        // Clear the timer
        highWattageTimer = nil
    }
    
    // MARK: Helper Methods
    
    private func createStyledMenuItem(title: String, suffix: String, action: Selector, value: Any, isSelected: Bool) -> NSMenuItem {
        let fullText = "\(title)  \(suffix)"
        let attributedTitle = NSMutableAttributedString(string: fullText)
        
        let suffixRange = (fullText as NSString).range(of: suffix)
        let smallFont = NSFont.systemFont(ofSize: 11)
        attributedTitle.addAttributes([
            .font: smallFont,
            .foregroundColor: NSColor.darkGray
        ], range: suffixRange)
        
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.attributedTitle = attributedTitle
        item.representedObject = value
        item.target = self
        item.state = isSelected ? .on : .off
        return item
    }
    
    private func detailLevelFormatString() -> String {
        let w = labelCase == .uppercase ? "W" : "w"
        switch detailLevel {
        case .low: return "%.0f\(w)"
        case .medium: return "%.1f\(w)"
        case .high: return "%.2f\(w)"
        }
    }
    
    private func estimateTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
    
    private func updateMenuStates(_ menu: NSMenu?, selectedValue: Any) {
        menu?.items.forEach { item in
            if item.representedObject as AnyObject? === selectedValue as AnyObject? {
                item.state = .on
            } else {
                item.state = .off
            }
        }
    }
    
    private func bindToPowerMonitor() {
        wattageSubscription = PowerMonitor.shared.$wattage
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateWattageDisplay()
            }
    }
    
    // MARK: Menu Actions
    
    @objc private func showMenu() {
        statusItemWattage?.button?.performClick(nil)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: Launch at Login
    
    private func checkLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Update menu item state if menu exists (hosted on wattage status item)
        if let menu = statusItemWattage?.menu {
            for item in menu.items {
                if let submenu = item.submenu,
                   let loginItem = submenu.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
                    loginItem.state = launchAtLogin ? .on : .off
                    break
                }
            }
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
                launchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            }
            
            // Update menu item state
            if let menu = statusItemWattage?.menu {
                for item in menu.items {
                    if let submenu = item.submenu,
                       let loginItem = submenu.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
                        loginItem.state = launchAtLogin ? .on : .off
                        break
                    }
                }
            }
        } catch let error as NSError {
            print("Error toggling launch at login: \(error.localizedDescription)")
            print("Error domain: \(error.domain), code: \(error.code)")
            if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                print("Reason: \(reason)")
            }
            
            let alert = NSAlert()
            alert.messageText = "Launch at Login Error"
            alert.informativeText = "Could not change launch at login setting: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
            // Reset the state to match the actual system state
            checkLaunchAtLoginStatus()
        }
    }
}

// MARK: - Power Monitor

class PowerMonitor: ObservableObject {
    
    static let shared = PowerMonitor()
    
    @Published var wattage: Double = 0.0
    
    private var timer: AnyCancellable?
    private var timerInterval: TimeInterval
    
    private init() {
        timerInterval = Double(PaceLevel.medium.rawValue)
        setupTimer()
    }
    
    func updatePace(_ pace: PaceLevel) {
        let newInterval = Double(pace.rawValue)
        guard newInterval != timerInterval else { return }
        timerInterval = newInterval
        setupTimer()
    }
    
    func fetchWattage() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let wattageValue = SMC.shared.getValue("PSTR") ?? 0.0
            DispatchQueue.main.async {
                self?.wattage = wattageValue
            }
        }
    }
    
    private func setupTimer() {
        timer?.cancel()
        timer = Timer.publish(every: timerInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchWattage()
            }
    }
}
