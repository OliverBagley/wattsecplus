//
//  main.swift
//  WattSec+
//
//  Replaces the SwiftUI @main App entry point with a minimal AppKit bootstrap.
//  LSUIElement: true in Info.plist keeps the app out of the Dock and app switcher.
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
