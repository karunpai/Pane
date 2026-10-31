import AppKit
import Carbon
import PaneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let windowManager = WindowManager()
    private var overlay: OverlayController!
    private var hotKeys: HotKeyManager!
    private var settings: SettingsWindowController?
    private let displayShortcuts = DisplayShortcutController()
    private var statusMenu: NSMenu?
    private var accessibilityStatusItem: NSMenuItem?
    private var lastShortcutID: UUID?
    private var lastShortcutScreen: NSScreen?
    private var isRecordingHotKey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(windowManager: windowManager)
        displayShortcuts.start()
        setupStatusItem()
        setupHotKeys()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange(_:)),
            name: AppPreferences.shortcutsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: AppPreferences.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyRecordingDidBegin(_:)),
            name: AppPreferences.hotKeyRecordingDidBeginNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyRecordingDidEnd(_:)),
            name: AppPreferences.hotKeyRecordingDidEndNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: AppPreferences.openSettingsRequestedNotification,
            object: nil
        )
        refreshAccessibilityStatus()
        if !launchedAsLoginItem() { openSettings() }
    }

    // Opening Pane again from Finder/Launchpad/Spotlight while it runs lands here; it is
    // also the way back to settings when the menu bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // Double-clicking a .paneshortcuts file in Finder (or dropping one on the app icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        importShortcutFiles(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        importShortcutFiles([URL(fileURLWithPath: filename)])
        return true
    }

    private var pendingShortcutFiles: [URL] = []
    private var isImportingShortcutFile = false

    private func importShortcutFiles(_ urls: [URL]) {
        let accepted = urls.filter { ["paneshortcuts", "json"].contains($0.pathExtension.lowercased()) }
        pendingShortcutFiles.append(contentsOf: accepted)
        importNextShortcutFile()
    }

    private func importNextShortcutFile() {
        guard !isImportingShortcutFile, !pendingShortcutFiles.isEmpty else { return }
        let url = pendingShortcutFiles.removeFirst()
        isImportingShortcutFile = true
        NSApp.activate(ignoringOtherApps: true)
        // Use the settings window as the sheet host when it's already on screen.
        let window = settings?.window?.isVisible == true ? settings?.window : nil
        ShortcutFileImporter.importFile(at: url, window: window) { [weak self] _ in
            self?.isImportingShortcutFile = false
            self?.importNextShortcutFile()
        }
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func setupStatusItem() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show Grid", action: #selector(showGrid), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Left Half", action: #selector(leftHalf), keyEquivalent: "")
        menu.addItem(withTitle: "Right Half", action: #selector(rightHalf), keyEquivalent: "")
        menu.addItem(withTitle: "Top Half", action: #selector(topHalf), keyEquivalent: "")
        menu.addItem(withTitle: "Bottom Half", action: #selector(bottomHalf), keyEquivalent: "")
        menu.addItem(withTitle: "Maximize", action: #selector(maximize), keyEquivalent: "")
        menu.addItem(.separator())
        let permissionStatus = menu.addItem(withTitle: "Accessibility: Checking…", action: nil, keyEquivalent: "")
        permissionStatus.isEnabled = false
        accessibilityStatusItem = permissionStatus
        menu.addItem(withTitle: "Accessibility Status & Recovery…", action: #selector(showAccessibilityStatus), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Pane", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusMenu = menu
        updateStatusItemVisibility()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAccessibilityStatus()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        let trusted = windowManager.requestAccessibilityPermission(prompt: false)
        accessibilityStatusItem?.title = trusted ? "Accessibility: Granted" : "Accessibility: Not Granted"
        statusItem?.button?.toolTip = trusted ? "Pane" : "Pane — Accessibility access required; right-click for recovery"
    }

    @objc private func showAccessibilityStatus() {
        let trusted = windowManager.requestAccessibilityPermission(prompt: false)
        refreshAccessibilityStatus()
        let alert = NSAlert()
        alert.messageText = trusted ? "Accessibility access is granted" : "Accessibility access is not granted"
        var details = trusted
            ? "Pane is trusted by macOS. A window may still refuse resizing or may no longer be available."
            : "Enable Pane in System Settings → Privacy & Security → Accessibility. Return to Pane and check this status again. If macOS still reports no access, quit and reopen the installed Pane app, then recheck."
        if let failure = windowManager.lastOperationFailure {
            details += "\n\nLast window-operation failure (not a permission diagnosis):\n\(failure)"
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Open System Settings")
        if !trusted { alert.addButton(withTitle: "Request Access") }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if !trusted && response == .alertThirdButtonReturn {
            _ = windowManager.requestAccessibilityPermission(prompt: true)
        }
        refreshAccessibilityStatus()
    }

    // The menu lives in statusMenu, so removing and re-adding the item keeps it intact.
    private func updateStatusItemVisibility() {
        if AppPreferences.shared.showMenuBar {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = paneTemplateImage()
            item.button?.setAccessibilityLabel("Pane")
            item.button?.toolTip = "Pane"
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupHotKeys() {
        if hotKeys == nil { hotKeys = HotKeyManager() }
        // While a shortcut recorder is capturing keys, stay unregistered so the
        // combination being typed can't fire a live action. End re-runs this.
        guard !isRecordingHotKey else { return }
        let prefs = AppPreferences.shared
        var shortcuts: [HotKeyManager.Shortcut] = []
        let panelModifiers = carbonModifiers(from: prefs.panelShortcutModifiers)
        if prefs.panelShortcutEnabled && panelModifiers != 0 {
            shortcuts.append(.init(name: "Show Grid", keyCode: prefs.panelShortcutKeyCode, modifiers: panelModifiers) { [weak self] in
                self?.overlay.toggle()
            })
        }
        for shortcut in ShortcutStore.shared.shortcuts where shortcut.isEnabled && shortcut.isGlobal {
            let modifiers = carbonModifiers(from: shortcut.cocoaModifiers)
            guard modifiers != 0 else { continue }
            shortcuts.append(.init(name: shortcut.name, keyCode: shortcut.keyCode, modifiers: modifiers) { [weak self] in
                self?.run(shortcut)
            })
        }
        let failures = hotKeys.register(shortcuts)
        NSLog("Pane: registered %d of %d shortcuts; Accessibility trusted: %@",
              shortcuts.count - failures.count, shortcuts.count, AXIsProcessTrusted() ? "yes" : "no")
        if !failures.isEmpty {
            NSLog("Pane: failed to register shortcuts: \(failures.joined(separator: ", "))")
        }
        NotificationCenter.default.post(
            name: AppPreferences.hotKeyRegistrationFailuresNotification,
            object: failures
        )
    }

    private func paneTemplateImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let frame = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 13, height: 13), xRadius: 2.2, yRadius: 2.2)
            frame.lineWidth = 1.2
            frame.stroke()

            let header = NSBezierPath()
            header.move(to: NSPoint(x: 3.5, y: 6.5))
            header.line(to: NSPoint(x: 14.5, y: 6.5))
            header.lineWidth = 1
            header.stroke()

            NSBezierPath(roundedRect: NSRect(x: 4, y: 8, width: 4, height: 6), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 8, width: 4, height: 2.5), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 11.5, width: 4, height: 2.5), xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        setupHotKeys()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        updateStatusItemVisibility()
        setupHotKeys()
    }

    @objc private func hotKeyRecordingDidBegin(_ notification: Notification) {
        isRecordingHotKey = true
        hotKeys?.unregisterAll()
    }

    @objc private func hotKeyRecordingDidEnd(_ notification: Notification) {
        isRecordingHotKey = false
        setupHotKeys()
    }

    private func carbonModifiers(from cocoa: UInt) -> UInt32 {
        var result: UInt32 = 0
        if cocoa & NSEvent.ModifierFlags.command.rawValue != 0 { result |= UInt32(cmdKey) }
        if cocoa & NSEvent.ModifierFlags.option.rawValue != 0 { result |= UInt32(optionKey) }
        if cocoa & NSEvent.ModifierFlags.control.rawValue != 0 { result |= UInt32(controlKey) }
        if cocoa & NSEvent.ModifierFlags.shift.rawValue != 0 { result |= UInt32(shiftKey) }
        return result
    }

    private func run(_ shortcut: WindowShortcut) {
        let previous = lastShortcutID == shortcut.id ? lastShortcutScreen : nil
        guard AXIsProcessTrusted() else {
            // Without Accessibility, moving windows silently fails. Ask instead.
            NSLog("Pane: shortcut '%@' pressed but Accessibility is not granted", shortcut.name)
            _ = windowManager.requestAccessibilityPermission(prompt: true)
            return
        }
        lastShortcutScreen = overlay.applyShortcut(shortcut, cycleFrom: previous)
        lastShortcutID = shortcut.id
    }

    private enum Preset { case left, right, top, bottom, full }
    private func apply(_ preset: Preset) {
        let rows = AppPreferences.shared.rows
        let columns = AppPreferences.shared.columns
        let midRow = max(0, rows / 2 - 1)
        let midColumn = max(0, columns / 2 - 1)
        let selection: GridSelection
        switch preset {
        case .left: selection = .init(startRow: 0, startColumn: 0, endRow: rows - 1, endColumn: midColumn)
        case .right: selection = .init(startRow: 0, startColumn: midColumn + 1, endRow: rows - 1, endColumn: columns - 1)
        case .top: selection = .init(startRow: 0, startColumn: 0, endRow: midRow, endColumn: columns - 1)
        case .bottom: selection = .init(startRow: midRow + 1, startColumn: 0, endRow: rows - 1, endColumn: columns - 1)
        case .full: selection = .init(startRow: 0, startColumn: 0, endRow: rows - 1, endColumn: columns - 1)
        }
        overlay.applyPreset(selection)
    }

    @objc private func showGrid() { overlay.toggle() }
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            if let statusMenu { statusItem?.popUpMenu(statusMenu) }
        } else {
            overlay.toggle()
        }
    }
    @objc private func leftHalf() { apply(.left) }
    @objc private func rightHalf() { apply(.right) }
    @objc private func topHalf() { apply(.top) }
    @objc private func bottomHalf() { apply(.bottom) }
    @objc private func maximize() { apply(.full) }
    @objc private func openSettings() {
        if settings == nil {
            settings = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }
    // Menu items target self, so Quit needs a selector AppDelegate actually implements.
    @objc private func quit() { NSApp.terminate(nil) }
}
