//
//  SettingsWindow.swift
//  WattSec+
//

import Cocoa
import Combine
import ServiceManagement

// MARK: - Appearance-adaptive glass card

/// A plain NSView that keeps its CALayer colours in sync with the system
/// appearance. Used for the frosted-glass section cards and their separators.
private final class GlassCardView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); setupLayer() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupLayer() }

    private func setupLayer() {
        wantsLayer = true
        layer?.cornerRadius  = 10
        layer?.masksToBounds = true
        layer?.borderWidth   = 0.5
        refreshColors()
    }

    private func refreshColors() {
        // Detect whether the effective appearance is dark (hudWindow is always
        // dark-ish, but adapt gracefully if the system ever renders it lighter).
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.07 : 0.04).cgColor
        layer?.borderColor     = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.11 : 0.08).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

/// A 0.5 pt horizontal separator whose colour adapts to dark / light mode.
private final class GlassSeparatorView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); setupLayer() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupLayer() }

    private func setupLayer() {
        wantsLayer = true
        refreshColors()
    }

    private func refreshColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.09 : 0.07).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

// MARK: - SettingsWindowController

final class SettingsWindowController: NSWindowController {

    weak var appDelegate: AppDelegate?

    // MARK: Controls

    private var detailControl:      NSSegmentedControl!
    private var paceControl:        NSSegmentedControl!
    private var widthControl:       NSSegmentedControl!
    private var fontSizeControl:    NSSegmentedControl!
    private var labelCaseControl:   NSSegmentedControl!
    private var showBatteryCheck:   NSButton!
    private var showUptimeCheck:    NSButton!
    private var uptimeCompactCheck: NSButton!
    private var uptimeMinutesCheck: NSButton!
    private var groupItemsCheck:    NSButton!
    private var showDashCheck:      NSButton!
    private var launchAtLoginCheck: NSButton!

    // Live preview — full attributed string display
    private var previewLabel: NSTextField!
    // Draggable order chips — lets user reorder components in grouped mode
    private var previewDragView: PreviewDragView!
    private var wattageSubscription: AnyCancellable?

    // Escape-key local monitor — released in deinit
    private var escMonitor: Any?

    // MARK: Init

    convenience init(appDelegate: AppDelegate) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 752),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "WattSec+"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed  = false
        win.backgroundColor       = .clear
        win.isOpaque              = false
        // macOS 13 + automatically rounds window edges; this ensures our
        // visual-effect layer also clips to the same radius.
        win.animationBehavior     = .utilityWindow

        // Liquid glass background: blurs the desktop content behind the window.
        let bg = NSVisualEffectView()
        bg.material      = .hudWindow
        bg.blendingMode  = .behindWindow
        bg.state         = .active
        bg.wantsLayer    = true
        bg.layer?.cornerRadius  = 12
        bg.layer?.masksToBounds = true
        win.contentView = bg

        self.init(window: win)
        self.appDelegate = appDelegate
        buildUI()
        syncControls()
        startLivePreview()
        installEscapeHandler()
    }

    deinit {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        wattageSubscription?.cancel()
    }

    // MARK: - Show with fade-in animation

    override func showWindow(_ sender: Any?) {
        guard let w = window else { return }
        w.alphaValue = 0
        super.showWindow(sender)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration         = 0.18
            ctx.timingFunction   = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1
        }
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment   = .leading
        outer.spacing     = 12
        outer.edgeInsets  = NSEdgeInsets(top: 44, left: 16, bottom: 20, right: 16)
        outer.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: cv.topAnchor),
            outer.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: cv.trailingAnchor)
        ])

        let W = CGFloat(328)     // card width = 360 window − 16 left − 16 right

        // Helper: add a section header then its card with a 4 pt gap.
        func section(_ title: String, _ card: NSView) {
            let lbl = sectionLabel(title)
            outer.addArrangedSubview(lbl)
            outer.setCustomSpacing(4, after: lbl)
            outer.addArrangedSubview(card)
        }

        // ── Live preview ─────────────────────────────────────────────────────
        // Top row: full attributed string — shows the exact menu bar output.
        previewLabel = NSTextField(labelWithString: "—")
        previewLabel.textColor = .labelColor
        previewLabel.alignment = .center

        let previewStringRow = NSView()
        previewStringRow.translatesAutoresizingMaskIntoConstraints = false
        previewStringRow.heightAnchor.constraint(equalToConstant: 34).isActive = true
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewStringRow.addSubview(previewLabel)
        NSLayoutConstraint.activate([
            previewLabel.leadingAnchor.constraint(equalTo: previewStringRow.leadingAnchor, constant: 12),
            previewLabel.trailingAnchor.constraint(equalTo: previewStringRow.trailingAnchor, constant: -12),
            previewLabel.centerYAnchor.constraint(equalTo: previewStringRow.centerYAnchor)
        ])

        // Bottom row: draggable component chips — drag to reorder (grouped mode).
        previewDragView = PreviewDragView()
        previewDragView.translatesAutoresizingMaskIntoConstraints = false
        previewDragView.onReorder = { [weak self] newOrder in
            let str = newOrder.joined(separator: ",")
            UserDefaults.standard.set(str, forKey: "componentOrder")
            self?.appDelegate?.applyChange(forKey: "componentOrder")
            self?.refreshPreview()   // update the full-string row immediately
        }

        let previewDragRow = NSView()
        previewDragRow.translatesAutoresizingMaskIntoConstraints = false
        previewDragRow.heightAnchor.constraint(equalToConstant: 56).isActive = true
        previewDragRow.addSubview(previewDragView)
        NSLayoutConstraint.activate([
            previewDragView.leadingAnchor.constraint(equalTo: previewDragRow.leadingAnchor),
            previewDragView.trailingAnchor.constraint(equalTo: previewDragRow.trailingAnchor),
            previewDragView.topAnchor.constraint(equalTo: previewDragRow.topAnchor),
            previewDragView.bottomAnchor.constraint(equalTo: previewDragRow.bottomAnchor)
        ])

        section("Preview", makeCard(W, rows: [previewStringRow, previewDragRow]))

        // ── Wattage ──────────────────────────────────────────────────────────
        detailControl = makeSeg(["Low", "Medium", "High"], action: #selector(detailChanged))
        paceControl   = makeSeg(["1s",  "3s",     "5s"],   action: #selector(paceChanged))
        widthControl  = makeSeg(["Dynamic", "Fixed"],       action: #selector(widthModeChanged))
        section("Wattage", makeCard(W, rows: [
            makeRow("Detail",    detailControl),
            makeRow("Pace",      paceControl),
            makeRow("Bar Width", widthControl)
        ]))

        // ── Appearance ───────────────────────────────────────────────────────
        fontSizeControl  = makeSeg(["XS", "S", "M", "L", "XL"], action: #selector(fontSizeChanged))
        labelCaseControl = makeSeg(["Uppercase", "Lowercase"],    action: #selector(labelCaseChanged))
        section("Appearance", makeCard(W, rows: [
            makeRow("Font Size", fontSizeControl),
            makeRow("Labels",    labelCaseControl)
        ]))

        // ── Menu Bar ─────────────────────────────────────────────────────────
        showBatteryCheck   = makeCheck("Show Battery",        action: #selector(showBatteryChanged))
        showUptimeCheck    = makeCheck("Show Uptime",         action: #selector(showUptimeChanged))
        uptimeCompactCheck = makeCheck("Compact format",      action: #selector(uptimeCompactChanged))
        uptimeMinutesCheck = makeCheck("Always show minutes", action: #selector(uptimeMinutesChanged))
        section("Menu Bar", makeCard(W, rows: [
            makeCheckRow(showBatteryCheck),
            makeCheckRow(showUptimeCheck),
            makeCheckRow(uptimeCompactCheck, indent: true),   // sub-option of Show Uptime
            makeCheckRow(uptimeMinutesCheck, indent: true)    // sub-option of Show Uptime
        ]))

        // ── Layout ───────────────────────────────────────────────────────────
        groupItemsCheck = makeCheck("Group into one item",  action: #selector(groupItemsChanged))
        showDashCheck   = makeCheck("Show dash separator",  action: #selector(showDashChanged))
        section("Layout", makeCard(W, rows: [
            makeCheckRow(groupItemsCheck),
            makeCheckRow(showDashCheck)
        ]))

        // ── System ───────────────────────────────────────────────────────────
        launchAtLoginCheck = makeCheck("Launch at Login", action: #selector(launchAtLoginChanged))
        section("System", makeCard(W, rows: [
            makeCheckRow(launchAtLoginCheck)
        ]))

        // ── Version footer ───────────────────────────────────────────────────
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let versionLabel = NSTextField(labelWithString: "WattSec+  \(version)")
        versionLabel.font      = .systemFont(ofSize: 10)
        versionLabel.textColor = .quaternaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.widthAnchor.constraint(equalToConstant: W).isActive = true
        outer.addArrangedSubview(versionLabel)
        outer.setCustomSpacing(8, after: outer.arrangedSubviews[outer.arrangedSubviews.count - 2])
    }

    // MARK: - Factory Helpers

    /// Appearance-adaptive glass card containing separator-divided rows.
    private func makeCard(_ width: CGFloat, rows: [NSView]) -> NSView {
        let card = GlassCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: width).isActive = true

        // Interleave rows with adaptive separators.
        var all:  [NSView] = []
        var seps: [NSView] = []
        for (i, row) in rows.enumerated() {
            all.append(row)
            if i < rows.count - 1 {
                let sep = GlassSeparatorView()
                all.append(sep)
                seps.append(sep)
            }
        }

        let vstack = NSStackView(views: all)
        vstack.orientation = .vertical
        vstack.alignment   = .leading
        vstack.spacing     = 0
        vstack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(vstack)
        NSLayoutConstraint.activate([
            vstack.topAnchor.constraint(equalTo: card.topAnchor),
            vstack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            vstack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            vstack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        // NSStackView sets translatesAutoresizingMaskIntoConstraints = false on
        // all arranged subviews; add height + width constraints after that.
        for sep in seps { sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true }
        for v   in all  { v.widthAnchor.constraint(equalTo: vstack.widthAnchor).isActive = true }

        return card
    }

    /// Labelled row: fixed-width label on the left, control on the right.
    private func makeRow(_ label: String, _ control: NSView) -> NSView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font      = .systemFont(ofSize: 12.5)
        lbl.textColor = .labelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let row = NSStackView(views: [lbl, control])
        row.orientation = .horizontal
        row.alignment   = .centerY
        row.spacing     = 8
        row.edgeInsets  = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    /// Full-width checkbox row, optionally indented to signal it's a sub-option.
    private func makeCheckRow(_ btn: NSButton, indent: Bool = false) -> NSView {
        let row = NSStackView(views: [btn])
        row.orientation = .horizontal
        row.alignment   = .centerY
        row.edgeInsets  = NSEdgeInsets(top: 0, left: indent ? 32 : 14, bottom: 0, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return row
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let f = NSTextField(labelWithString: title.uppercased())
        f.font      = .systemFont(ofSize: 10, weight: .semibold)
        f.textColor = .tertiaryLabelColor
        return f
    }

    private func makeSeg(_ labels: [String], action: Selector) -> NSSegmentedControl {
        let s = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                   target: self, action: action)
        s.segmentStyle = .rounded
        s.controlSize  = .small
        return s
    }

    private func makeCheck(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        b.font = .systemFont(ofSize: 12.5)
        return b
    }

    // MARK: - Live Preview

    private func startLivePreview() {
        wattageSubscription = PowerMonitor.shared.$wattage
            .debounce(for: .seconds(0.05), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPreview() }
    }

    private func refreshPreview() {
        guard let delegate = appDelegate else {
            previewLabel.stringValue = "—"
            return
        }

        // Full-string row — exact attributed string shown in the real menu bar.
        let raw = delegate.buildMenuBarAttributedString()
        let centered = NSMutableAttributedString(attributedString: raw)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        centered.addAttribute(.paragraphStyle, value: para,
                              range: NSRange(location: 0, length: centered.length))
        previewLabel.attributedStringValue = centered

        // Drag chips row — individual component strings + current order.
        previewDragView.update(order: delegate.componentOrder,
                               components: delegate.componentAttributedStrings())
    }

    // MARK: - Uptime sub-option gating

    /// Dims and disables the uptime sub-options when Show Uptime is off.
    private func updateUptimeSubOptions() {
        let on = showUptimeCheck.state == .on
        uptimeCompactCheck.isEnabled = on
        uptimeMinutesCheck.isEnabled = on
        // Fade controls that don't apply to signal they're inactive.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            uptimeCompactCheck.animator().alphaValue  = on ? 1.0 : 0.35
            uptimeMinutesCheck.animator().alphaValue  = on ? 1.0 : 0.35
        }
    }

    // MARK: - Escape key

    private func installEscapeHandler() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.window, event.keyCode == 53 else { return event }
            self.close()
            return nil
        }
    }

    // MARK: - Sync controls → current UserDefaults state

    /// Refreshes every control from UserDefaults and live SMAppService status.
    /// Called once at init and again each time the window is shown so the UI
    /// stays in sync with changes made via the right-click menu.
    func syncControls() {
        let d = UserDefaults.standard

        detailControl.selectedSegment    = d.integer(forKey: "detailLevel")   // 0/1/2 maps directly

        let pace = d.integer(forKey: "paceLevel")
        paceControl.selectedSegment      = pace == 1 ? 0 : pace == 3 ? 1 : 2  // 1s→0, 3s→1, 5s→2

        widthControl.selectedSegment     = (d.string(forKey: "widthMode") ?? "dynamic") == "dynamic" ? 0 : 1
        fontSizeControl.selectedSegment  = d.integer(forKey: "fontSize")        // 0–4 maps directly
        labelCaseControl.selectedSegment = (d.string(forKey: "labelCase") ?? "lowercase") == "uppercase" ? 0 : 1

        showBatteryCheck.state   = d.bool(forKey: "showBattery")        ? .on : .off
        showUptimeCheck.state    = d.bool(forKey: "showUptime")         ? .on : .off
        uptimeCompactCheck.state = d.bool(forKey: "uptimeCompact")      ? .on : .off
        uptimeMinutesCheck.state = d.bool(forKey: "uptimeShowMinutes")  ? .on : .off
        groupItemsCheck.state    = d.bool(forKey: "groupStatusItems")   ? .on : .off
        showDashCheck.state      = d.bool(forKey: "showDash")           ? .on : .off

        // Read live from SMAppService — not stored in UserDefaults.
        launchAtLoginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Seed drag view order from live AppDelegate state.
        if let delegate = appDelegate {
            previewDragView.setOrder(delegate.componentOrder)
        }

        updateUptimeSubOptions()
        refreshPreview()
    }

    // MARK: - Actions

    @objc private func detailChanged() {
        UserDefaults.standard.set(detailControl.selectedSegment, forKey: "detailLevel")
        appDelegate?.applyChange(forKey: "detailLevel")
        refreshPreview()
    }

    @objc private func paceChanged() {
        let raw = [1, 3, 5][paceControl.selectedSegment]
        UserDefaults.standard.set(raw, forKey: "paceLevel")
        appDelegate?.applyChange(forKey: "paceLevel")
    }

    @objc private func widthModeChanged() {
        let raw = widthControl.selectedSegment == 0 ? "dynamic" : "fixed"
        UserDefaults.standard.set(raw, forKey: "widthMode")
        appDelegate?.applyChange(forKey: "widthMode")
    }

    @objc private func fontSizeChanged() {
        UserDefaults.standard.set(fontSizeControl.selectedSegment, forKey: "fontSize")
        appDelegate?.applyChange(forKey: "fontSize")
        refreshPreview()
    }

    @objc private func labelCaseChanged() {
        let raw = labelCaseControl.selectedSegment == 0 ? "uppercase" : "lowercase"
        UserDefaults.standard.set(raw, forKey: "labelCase")
        appDelegate?.applyChange(forKey: "labelCase")
        refreshPreview()     // preview immediately reflects case change
    }

    @objc private func showBatteryChanged() {
        UserDefaults.standard.set(showBatteryCheck.state == .on, forKey: "showBattery")
        appDelegate?.applyChange(forKey: "showBattery")
        refreshPreview()
    }

    @objc private func showUptimeChanged() {
        UserDefaults.standard.set(showUptimeCheck.state == .on, forKey: "showUptime")
        appDelegate?.applyChange(forKey: "showUptime")
        updateUptimeSubOptions()
        refreshPreview()
    }

    @objc private func uptimeCompactChanged() {
        UserDefaults.standard.set(uptimeCompactCheck.state == .on, forKey: "uptimeCompact")
        appDelegate?.applyChange(forKey: "uptimeCompact")
        refreshPreview()
    }

    @objc private func uptimeMinutesChanged() {
        UserDefaults.standard.set(uptimeMinutesCheck.state == .on, forKey: "uptimeShowMinutes")
        appDelegate?.applyChange(forKey: "uptimeShowMinutes")
        refreshPreview()
    }

    @objc private func groupItemsChanged() {
        UserDefaults.standard.set(groupItemsCheck.state == .on, forKey: "groupStatusItems")
        appDelegate?.applyChange(forKey: "groupStatusItems")
        refreshPreview()
    }

    @objc private func showDashChanged() {
        UserDefaults.standard.set(showDashCheck.state == .on, forKey: "showDash")
        appDelegate?.applyChange(forKey: "showDash")
        refreshPreview()
    }

    @objc private func launchAtLoginChanged() {
        appDelegate?.applyLaunchAtLoginChange()
        // Re-read live SMAppService state a tick later in case the OS denied the change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.launchAtLoginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

// MARK: - Draggable component chip

/// A single draggable chip in the preview row, showing one menu-bar component
/// (battery, wattage, or uptime) as an attributed string.
private final class ChipView: NSView {
    private let label = NSTextField(labelWithString: "")

    /// Intrinsic pixel width of the chip content (add horizontal padding on top).
    var contentWidth: CGFloat {
        let w = label.intrinsicContentSize.width
        return w > 0 ? w + 4 : 28   // +4 for text-attachment safety margin
    }

    override init(frame: NSRect) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth   = 0.5
        refreshColors()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment     = .center
        label.isEditable    = false
        label.isBordered    = false
        label.backgroundColor = .clear
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setContent(_ str: NSAttributedString) {
        label.attributedStringValue = str
    }

    // Returning false prevents AppKit from treating a mouseDown on this view
    // (or its non-opaque NSTextField label child) as a window-background drag.
    override var mouseDownCanMoveWindow: Bool { false }

    // Always return self — stops the inner NSTextField label from being the
    // deepest hit-tested view and intercepting events before PreviewDragView.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // Accept first-mouse so a single click-drag works even when the settings
    // window is not currently the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func refreshColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.13 : 0.07).cgColor
        layer?.borderColor     = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.20 : 0.10).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

// MARK: - Preview drag view

/// Horizontal row of draggable chips — one per visible display component.
/// Drag a chip past its neighbour to swap their positions.
/// Calls `onReorder` with the full 3-element order array when the user releases.
final class PreviewDragView: NSView {

    var onReorder: (([String]) -> Void)?

    private(set) var order: [String] = ["battery", "wattage", "uptime"]
    private var visible: Set<String> = []
    private var chips: [String: ChipView] = [:]
    private let hintLabel = NSTextField(labelWithString: "Double click and drag to reorder")

    // Drag state
    private var dragComp: String?
    private var dragStartMouseX: CGFloat = 0
    private var dragStartChipX: CGFloat  = 0
    private var isDragging = false

    private let chipH:       CGFloat = 26
    private let chipPadH:    CGFloat = 10   // horizontal padding inside each chip
    private let chipSpacing: CGFloat = 8
    private let hintLabelGap : CGFloat = 14

    // Prevent the drag row background from participating in window-background
    // dragging — events must reach mouseDown/mouseDragged/mouseUp instead.
    override var mouseDownCanMoveWindow: Bool { false }

    // Accept first-mouse so the first click into an inactive settings window
    // goes straight to chip dragging rather than just focusing the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        for comp in ["battery", "wattage", "uptime"] {
            let chip = ChipView()
            chip.isHidden = true
            addSubview(chip)
            chips[comp] = chip
        }

        hintLabel.font      = .systemFont(ofSize: 9)
        hintLabel.textColor = .quaternaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isHidden  = true
        addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Content update

    /// Refresh chip content and visibility.
    /// `components` contains attributed strings only for currently-enabled components.
    func update(order: [String], components: [String: NSAttributedString]) {
        self.order   = order
        self.visible = Set(components.keys)
        for comp in ["battery", "wattage", "uptime"] {
            if let str = components[comp] {
                chips[comp]?.setContent(str)
                chips[comp]?.isHidden = false
            } else {
                chips[comp]?.isHidden = true
            }
        }
        hintLabel.isHidden = visible.count < 2
        if !isDragging { layoutChips(animated: false) }
    }

    /// Sync the order without changing chip content (e.g. on syncControls).
    func setOrder(_ newOrder: [String]) {
        order = newOrder
        if !isDragging { layoutChips(animated: false) }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        if !isDragging { layoutChips(animated: false) }
    }

    private func visibleOrder() -> [String] {
        order.filter { visible.contains($0) }
    }

    private func layoutChips(animated: Bool) {
        let vo = visibleOrder()
        guard !vo.isEmpty, bounds.width > 0 else { return }

        // Measure each visible chip
        var widths: [String: CGFloat] = [:]
        var totalW: CGFloat = CGFloat(max(0, vo.count - 1)) * chipSpacing
        for comp in vo {
            let w = (chips[comp]?.contentWidth ?? 28) + chipPadH * 2
            widths[comp] = w
            totalW += w
        }

        // Reserve hintLabelGap pt at the bottom for the hint label, then vertically
        // centre chips in the remaining upper portion. hintReserve is the y-floor
        // so chips are always above the hint text.
        let hintReserve: CGFloat = visible.count >= 2 ? hintLabelGap : 0
        let usableH = bounds.height - hintReserve
        let chipY   = hintReserve + max(0, (usableH - chipH) / 2)
        var x = max(0, (bounds.width - totalW) / 2)

        let block = {
            for comp in vo {
                guard let chip = self.chips[comp], let w = widths[comp] else { continue }
                // Leave the actively-dragged chip at its current position
                if self.isDragging && self.dragComp == comp {
                    x += w + self.chipSpacing; continue
                }
                chip.frame = CGRect(x: x, y: chipY, width: w, height: self.chipH)
                x += w + self.chipSpacing
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                block()
            }
        } else {
            block()
        }
    }

    // MARK: - Mouse drag

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        for comp in visibleOrder() {
            guard let chip = chips[comp], chip.frame.contains(pt) else { continue }
            dragComp       = comp
            dragStartMouseX = pt.x
            dragStartChipX  = chip.frame.origin.x
            isDragging      = false
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let comp = dragComp, let chip = chips[comp] else { return }
        let pt    = convert(event.locationInWindow, from: nil)
        let delta = pt.x - dragStartMouseX
        guard abs(delta) >= 4 || isDragging else { return }

        if !isDragging {
            isDragging = true
            NSCursor.closedHand.push()
        }

        // Clamp to view bounds so the chip can't be dragged fully off-screen
        chip.frame.origin.x = max(0, min(bounds.width - chip.frame.width,
                                         dragStartChipX + delta))

        // Check if we've crossed a neighbour's midpoint → swap
        let vo = visibleOrder()
        guard let idx = vo.firstIndex(of: comp) else { return }
        let center = chip.frame.midX

        if idx < vo.count - 1,
           let right = chips[vo[idx + 1]],
           center > right.frame.midX,
           let oi = order.firstIndex(of: comp),
           let ri = order.firstIndex(of: vo[idx + 1]) {
            order.swapAt(oi, ri)
            layoutChips(animated: true)
        } else if idx > 0,
                  let left = chips[vo[idx - 1]],
                  center < left.frame.midX,
                  let oi = order.firstIndex(of: comp),
                  let li = order.firstIndex(of: vo[idx - 1]) {
            order.swapAt(oi, li)
            layoutChips(animated: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragComp != nil else { return }
        if isDragging { NSCursor.pop() }
        isDragging = false
        dragComp   = nil
        layoutChips(animated: true)
        onReorder?(order)
    }

    override func resetCursorRects() {
        for comp in visibleOrder() {
            if let chip = chips[comp], !chip.isHidden {
                addCursorRect(chip.frame, cursor: .openHand)
            }
        }
    }
}
