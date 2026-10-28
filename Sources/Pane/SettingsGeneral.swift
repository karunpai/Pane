import AppKit
import ApplicationServices
import ServiceManagement

final class GeneralPreferencesViewController: NSViewController {
    private let prefs = AppPreferences.shared
    private var shortcutRecorder = ShortcutRecorderButton()
    private let accessibilityIcon = NSImageView()
    private let accessibilityText = NSTextField(labelWithString: "")

    override func loadView() {
        let form = SettingsForm()
        let width = SettingsMetrics.controlColumnWidth

        form.row("Application:", checkbox("Start Pane at login", state: SMAppService.mainApp.status == .enabled,
                                          target: self, action: #selector(toggleLaunchAtLogin(_:))))
        form.row(nil, checkbox("Show Pane in the menu bar", state: prefs.showMenuBar,
                               target: self, action: #selector(toggleMenuBar(_:))))
        let panelRow = form.row("Panel:", checkbox("Keep panel open until dismissed", state: prefs.keepOpen,
                                                   target: self, action: #selector(toggleKeepOpen(_:))))
        form.gap(before: panelRow)
        form.row(nil, checkbox("Cycle between displays when repeating a shortcut", state: prefs.cycleDisplays,
                               target: self, action: #selector(toggleCycleDisplays(_:))))

        shortcutRecorder = ShortcutRecorderButton(keyCode: prefs.panelShortcutKeyCode, modifiers: prefs.panelShortcutModifiers)
        shortcutRecorder.isEnabled = prefs.panelShortcutEnabled
        shortcutRecorder.onChange = { [weak self] keyCode, modifiers in
            guard let self else { return }
            do {
                try self.prefs.updatePanelShortcut(
                    enabled: self.prefs.panelShortcutEnabled,
                    keyCode: keyCode,
                    modifiers: modifiers,
                    validating: ShortcutStore.shared.shortcuts
                )
            } catch {
                self.shortcutRecorder.setShortcut(keyCode: self.prefs.panelShortcutKeyCode,
                                                  modifiers: self.prefs.panelShortcutModifiers)
                self.presentPanelShortcutError(error)
            }
        }
        let shortcutToggle = checkbox("Show the panel with", state: prefs.panelShortcutEnabled,
                                      target: self, action: #selector(togglePanelShortcut(_:)))
        let shortcutRow = form.row("Panel shortcut:", hStack([shortcutToggle, shortcutRecorder]))
        form.gap(before: shortcutRow)

        form.separator()
        accessibilityIcon.setContentHuggingPriority(.required, for: .horizontal)
        accessibilityText.lineBreakMode = .byTruncatingTail
        let status = hStack([accessibilityIcon, accessibilityText], spacing: 6)
        status.alignment = .centerY
        form.row("Accessibility:", status)
        form.row(nil, pushButton("Open Privacy Settings…", target: self, action: #selector(openPrivacySettings)))
        refreshAccessibilityStatus()

        form.separator()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        form.row("Version:", label(version))
        form.row(nil, wrappingNote("New versions are published on GitHub. Download the latest DMG from github.com/karunpai/Pane/releases and replace Pane in Applications.", width: width))

        let help = NSButton(title: "", target: self, action: #selector(showHelp))
        help.bezelStyle = .helpButton
        help.toolTip = "Using Pane"
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = SettingsMetrics.spacing
        footer.addView(help, in: .leading)
        footer.addView(pushButton("About Pane", target: self, action: #selector(showAbout)), in: .trailing)
        footer.addView(pushButton("Quit Pane", target: self, action: #selector(quit)), in: .trailing)

        view = makeFormTabView(form: form, footer: footer, for: self)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAccessibilityStatus()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else { return }
        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let symbol = trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        accessibilityIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: trusted ? "Granted" : "Not granted")?
            .withSymbolConfiguration(config)
        accessibilityIcon.contentTintColor = trusted ? .systemGreen : .systemOrange
        accessibilityText.stringValue = trusted
            ? "Pane can move and resize windows"
            : "Pane needs Accessibility access to move windows"
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = sender.state == .on ? .off : .on
            NSAlert(error: error).runModal()
        }
    }

    @objc private func toggleMenuBar(_ sender: NSButton) { prefs.showMenuBar = sender.state == .on }
    @objc private func toggleKeepOpen(_ sender: NSButton) { prefs.keepOpen = sender.state == .on }
    @objc private func toggleCycleDisplays(_ sender: NSButton) { prefs.cycleDisplays = sender.state == .on }
    @objc private func togglePanelShortcut(_ sender: NSButton) {
        let enabled = sender.state == .on
        do {
            try prefs.updatePanelShortcut(
                enabled: enabled,
                keyCode: prefs.panelShortcutKeyCode,
                modifiers: prefs.panelShortcutModifiers,
                validating: ShortcutStore.shared.shortcuts
            )
            shortcutRecorder.isEnabled = enabled
        } catch {
            sender.state = prefs.panelShortcutEnabled ? .on : .off
            shortcutRecorder.isEnabled = prefs.panelShortcutEnabled
            presentPanelShortcutError(error)
        }
    }

    private func presentPanelShortcutError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Shortcut Conflict"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window = view.window { alert.beginSheetModal(for: window) }
    }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Using Pane"
        alert.informativeText = "Use the panel shortcut or menu-bar icon to open the grid. Drag across cells to resize the frontmost window. Hold Option for a subdivided grid. Pane needs Accessibility permission to move windows."
        alert.addButton(withTitle: "OK")
        if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
