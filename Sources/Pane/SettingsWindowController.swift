import AppKit
import Carbon
import PaneCore
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pane Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab(GeneralPreferencesViewController(), title: "General", symbol: "gearshape"))
        tabs.addTabViewItem(Self.tab(AppearancePreferencesViewController(), title: "Appearance", symbol: "paintbrush"))
        tabs.addTabViewItem(Self.tab(ShortcutsPreferencesViewController(), title: "Shortcuts", symbol: "command"))
        window.contentViewController = tabs
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
    }

    private static func tab(_ controller: NSViewController, title: String, symbol: String) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

private final class GeneralPreferencesViewController: NSViewController {
    private let prefs = AppPreferences.shared
    private var shortcutRecorder = ShortcutRecorderButton()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let stack = verticalStack(in: view)
        stack.addArrangedSubview(sectionTitle("Application"))
        stack.addArrangedSubview(checkbox("Start Pane at login", state: SMAppService.mainApp.status == .enabled, target: self, action: #selector(toggleLaunchAtLogin(_:))))
        stack.addArrangedSubview(checkbox("Show Pane in the menu bar", state: prefs.showMenuBar, target: self, action: #selector(toggleMenuBar(_:))))
        stack.addArrangedSubview(checkbox("Keep panel open until dismissed", state: prefs.keepOpen, target: self, action: #selector(toggleKeepOpen(_:))))
        stack.addArrangedSubview(checkbox("Cycle between displays when repeating a shortcut", state: prefs.cycleDisplays, target: self, action: #selector(toggleCycleDisplays(_:))))

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Panel Shortcut"))
        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 12
        shortcutRow.addArrangedSubview(checkbox("Use a global shortcut to show the panel", state: prefs.panelShortcutEnabled, target: self, action: #selector(togglePanelShortcut(_:))))
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
                self.shortcutRecorder.setShortcut(
                    keyCode: self.prefs.panelShortcutKeyCode,
                    modifiers: self.prefs.panelShortcutModifiers
                )
                self.presentPanelShortcutError(error)
            }
        }
        shortcutRow.addArrangedSubview(shortcutRecorder)
        stack.addArrangedSubview(shortcutRow)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Updates"))
        let updates = NSTextField(wrappingLabelWithString: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"). To update, run scripts/update.sh in the Pane folder. New versions are published to the private GitHub repo.")
        updates.textColor = .secondaryLabelColor
        updates.maximumNumberOfLines = 2
        stack.addArrangedSubview(updates)

        let spacer = NSView()
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        stack.addArrangedSubview(spacer)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(button("About Pane", target: self, action: #selector(showAbout)))
        buttons.addArrangedSubview(button("Help", target: self, action: #selector(showHelp)))
        buttons.addArrangedSubview(button("Quit Pane", target: self, action: #selector(quit)))
        stack.addArrangedSubview(buttons)
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
        alert.runModal()
    }
}

private final class AppearancePreferencesViewController: NSViewController, NSTextFieldDelegate {
    private let prefs = AppPreferences.shared
    private var fields: [String: NSTextField] = [:]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let stack = verticalStack(in: view)
        stack.addArrangedSubview(sectionTitle("Grid"))
        stack.addArrangedSubview(numberRow("Rows", key: "rows", value: Double(prefs.rows), suffix: "1–10"))
        stack.addArrangedSubview(numberRow("Columns", key: "columns", value: Double(prefs.columns), suffix: "1–10"))
        stack.addArrangedSubview(checkbox("Show resize preview", state: prefs.showPreview, target: self, action: #selector(togglePreview(_:))))

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Window Spacing"))
        stack.addArrangedSubview(checkbox("Use gaps and screen margins", state: prefs.marginsEnabled, target: self, action: #selector(toggleMargins(_:))))
        stack.addArrangedSubview(numberRow("Horizontal gap", key: "horizontalGap", value: prefs.horizontalGap, suffix: "pt"))
        stack.addArrangedSubview(numberRow("Vertical gap", key: "verticalGap", value: prefs.verticalGap, suffix: "pt"))

        let margins = NSGridView(views: [
            [label("Left"), numberField("marginLeft", prefs.marginLeft), label("Right"), numberField("marginRight", prefs.marginRight)],
            [label("Top"), numberField("marginTop", prefs.marginTop), label("Bottom"), numberField("marginBottom", prefs.marginBottom)]
        ])
        margins.rowSpacing = 10
        margins.columnSpacing = 10
        stack.addArrangedSubview(margins)

        let note = NSTextField(wrappingLabelWithString: "Changes apply to the next preview or window move and are saved automatically.")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
    }

    private func numberRow(_ title: String, key: String, value: Double, suffix: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        let titleLabel = label(title)
        titleLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(numberField(key, value))
        let suffixLabel = label(suffix)
        suffixLabel.textColor = .secondaryLabelColor
        row.addArrangedSubview(suffixLabel)
        return row
    }

    private func numberField(_ key: String, _ value: Double) -> NSTextField {
        let field = NSTextField(string: value.rounded() == value ? String(Int(value)) : String(value))
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.delegate = self
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        fields[key] = field
        return field
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let key = field.identifier?.rawValue,
              let value = Double(field.stringValue) else { return }
        switch key {
        case "rows": prefs.rows = Int(value)
        case "columns": prefs.columns = Int(value)
        case "horizontalGap": prefs.horizontalGap = value
        case "verticalGap": prefs.verticalGap = value
        case "marginLeft": prefs.marginLeft = value
        case "marginRight": prefs.marginRight = value
        case "marginTop": prefs.marginTop = value
        case "marginBottom": prefs.marginBottom = value
        default: return
        }
        refreshFields()
    }

    private func refreshFields() {
        fields["rows"]?.integerValue = prefs.rows
        fields["columns"]?.integerValue = prefs.columns
        fields["horizontalGap"]?.doubleValue = prefs.horizontalGap
        fields["verticalGap"]?.doubleValue = prefs.verticalGap
        fields["marginLeft"]?.doubleValue = prefs.marginLeft
        fields["marginRight"]?.doubleValue = prefs.marginRight
        fields["marginTop"]?.doubleValue = prefs.marginTop
        fields["marginBottom"]?.doubleValue = prefs.marginBottom
    }

    @objc private func togglePreview(_ sender: NSButton) { prefs.showPreview = sender.state == .on }
    @objc private func toggleMargins(_ sender: NSButton) { prefs.marginsEnabled = sender.state == .on }
}

private final class ShortcutsPreferencesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let store = ShortcutStore.shared
    private var shortcuts: [WindowShortcut] = []
    private let table = NSTableView()
    private let nameField = NSTextField()
    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let globalButton = NSButton(checkboxWithTitle: "Global", target: nil, action: nil)
    private let keyRecorder = ShortcutRecorderButton()
    private var detailFields: [String: NSTextField] = [:]
    private let registrationStatus = NSTextField(labelWithString: "")
    private var activeEditor: ShortcutEditorWindowController?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        shortcuts = store.shortcuts
        buildTable()
        buildManagerActions()
        table.reloadData()
        if !shortcuts.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        refreshEditor()
        NotificationCenter.default.addObserver(self, selector: #selector(showRegistrationFailures(_:)), name: AppPreferences.hotKeyRegistrationFailuresNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storedShortcutsDidChange(_:)), name: AppPreferences.shortcutsDidChangeNotification, object: nil)
    }

    private func buildTable() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -72)
        ])

        for (id, title, width) in [("enabled", "On", 42.0), ("name", "Name", 175.0), ("shortcut", "Shortcut", 100.0), ("scope", "Scope", 60.0), ("grid", "Grid", 55.0), ("layout", "Placement", 145.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 44
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(editShortcut)
        scroll.documentView = table
    }

    private func buildManagerActions() {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22)
        ])
        bar.addArrangedSubview(button("New…", target: self, action: #selector(newShortcut)))
        bar.addArrangedSubview(button("Edit…", target: self, action: #selector(editShortcut)))
        bar.addArrangedSubview(button("Delete", target: self, action: #selector(deleteShortcut)))
        bar.addArrangedSubview(button("Import…", target: self, action: #selector(importShortcuts)))
        bar.addArrangedSubview(button("Export…", target: self, action: #selector(exportShortcuts)))
        registrationStatus.textColor = .systemRed
        registrationStatus.lineBreakMode = .byTruncatingTail
        bar.addArrangedSubview(registrationStatus)
    }

    private func buildEditor() {
        let editor = NSStackView()
        editor.orientation = .vertical
        editor.alignment = .leading
        editor.spacing = 10
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            editor.topAnchor.constraint(equalTo: view.topAnchor, constant: 278)
        ])

        let first = NSStackView()
        first.orientation = .horizontal
        first.spacing = 10
        first.addArrangedSubview(label("Name"))
        nameField.widthAnchor.constraint(equalToConstant: 230).isActive = true
        first.addArrangedSubview(nameField)
        enabledButton.target = self
        enabledButton.action = #selector(saveEditor)
        globalButton.target = self
        globalButton.action = #selector(saveEditor)
        first.addArrangedSubview(enabledButton)
        first.addArrangedSubview(globalButton)
        first.addArrangedSubview(label("Shortcut"))
        keyRecorder.onChange = { [weak self] keyCode, modifiers in
            guard let self, self.table.selectedRow >= 0 else { return }
            var proposed = self.shortcuts
            proposed[self.table.selectedRow].keyCode = keyCode
            proposed[self.table.selectedRow].cocoaModifiers = modifiers
            if !self.persistAndReload(proposed, selectedRow: self.table.selectedRow) {
                let saved = self.shortcuts[self.table.selectedRow]
                self.keyRecorder.setShortcut(keyCode: saved.keyCode, modifiers: saved.cocoaModifiers)
            }
        }
        first.addArrangedSubview(keyRecorder)
        editor.addArrangedSubview(first)

        let values: [(String, String)] = [
            ("Rows", "rows"), ("Columns", "columns"),
            ("Start row", "startRow"), ("Start column", "startColumn"),
            ("End row", "endRow"), ("End column", "endColumn")
        ]
        let grid = NSGridView()
        for index in stride(from: 0, to: values.count, by: 3) {
            var cells: [NSView] = []
            for item in values[index..<min(index + 3, values.count)] {
                cells.append(label(item.0))
                let field = NSTextField()
                field.identifier = NSUserInterfaceItemIdentifier(item.1)
                field.delegate = self
                field.alignment = .right
                field.widthAnchor.constraint(equalToConstant: 52).isActive = true
                detailFields[item.1] = field
                cells.append(field)
            }
            grid.addRow(with: cells)
        }
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        editor.addArrangedSubview(grid)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.addArrangedSubview(button("Save Changes", target: self, action: #selector(saveEditor)))
        actions.addArrangedSubview(button("Import…", target: self, action: #selector(importShortcuts)))
        actions.addArrangedSubview(button("Export…", target: self, action: #selector(exportShortcuts)))
        let note = label("Import lets you merge with or replace your shortcuts.")
        note.textColor = .secondaryLabelColor
        actions.addArrangedSubview(note)
        editor.addArrangedSubview(actions)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shortcuts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let shortcut = shortcuts[row]
        if id == "enabled" {
            return NSTextField(labelWithString: shortcut.isEnabled ? "✓" : "—")
        }
        if id == "layout" {
            let thumbnail = ShortcutMiniGridView(shortcut: shortcut)
            thumbnail.toolTip = "Rows \(shortcut.selection.startRow + 1)–\(shortcut.selection.endRow + 1), columns \(shortcut.selection.startColumn + 1)–\(shortcut.selection.endColumn + 1)"
            return thumbnail
        }
        let value: String
        switch id {
        case "name": value = shortcut.name
        case "shortcut": value = shortcutDisplay(keyCode: shortcut.keyCode, modifiers: shortcut.cocoaModifiers)
        case "scope": value = shortcut.isGlobal ? "Global" : "Stored"
        case "grid": value = "\(shortcut.columns)×\(shortcut.rows)"
        default: value = ""
        }
        let text = NSTextField(labelWithString: value)
        text.lineBreakMode = .byTruncatingTail
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) { refreshEditor() }

    @objc private func newShortcut() {
        let prefs = AppPreferences.shared
        let shortcut = WindowShortcut(
            name: "New Shortcut", keyCode: UInt32(kVK_ANSI_N),
            cocoaModifiers: NSEvent.ModifierFlags([.command, .option]).rawValue,
            isGlobal: true, isEnabled: false, rows: prefs.rows, columns: prefs.columns,
            isSubdivided: false,
            selection: GridSelection(startRow: 0, startColumn: 0, endRow: prefs.rows - 1, endColumn: prefs.columns - 1)
        )
        presentEditor(shortcut, replacing: nil)
    }

    @objc private func editShortcut() {
        let row = table.selectedRow
        guard shortcuts.indices.contains(row) else { NSSound.beep(); return }
        presentEditor(shortcuts[row], replacing: row)
    }

    private func presentEditor(_ shortcut: WindowShortcut, replacing index: Int?) {
        guard let parent = view.window else { return }
        let editor = ShortcutEditorWindowController(shortcut: shortcut, otherShortcuts: shortcuts.enumerated().compactMap { $0.offset == index ? nil : $0.element })
        activeEditor = editor
        editor.onSave = { [weak self, weak editor] saved in
            guard let self else { return }
            var proposed = self.shortcuts
            if let index { proposed[index] = saved }
            else { proposed.append(saved) }
            let selectedRow = index ?? proposed.count - 1
            guard self.persistAndReload(proposed, selectedRow: selectedRow) else { return }
            if let child = editor?.window { parent.endSheet(child) }
            self.activeEditor = nil
        }
        editor.onCancel = { [weak self, weak editor] in
            if let child = editor?.window { parent.endSheet(child) }
            self?.activeEditor = nil
        }
        guard let child = editor.window else { return }
        parent.beginSheet(child)
    }

    @objc private func deleteShortcut() {
        let row = table.selectedRow
        guard shortcuts.indices.contains(row), let window = view.window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(shortcuts[row].name)”?"
        alert.informativeText = "This removes the shortcut from Pane. This action cannot be undone after the settings window is closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var proposed = self.shortcuts
            proposed.remove(at: row)
            _ = self.persistAndReload(proposed, selectedRow: proposed.isEmpty ? nil : min(row, proposed.count - 1))
        }
    }

    @objc private func showRegistrationFailures(_ notification: Notification) {
        let failures = notification.object as? [String] ?? []
        registrationStatus.stringValue = failures.isEmpty ? "" : "Could not register: \(failures.joined(separator: ", "))"
        registrationStatus.toolTip = registrationStatus.stringValue
    }

    private func refreshEditor() {
        let row = table.selectedRow
        let enabled = row >= 0 && row < shortcuts.count
        [nameField, enabledButton, globalButton, keyRecorder].forEach { $0.isEnabled = enabled }
        detailFields.values.forEach { $0.isEnabled = enabled }
        guard enabled else { return }
        let shortcut = shortcuts[row]
        nameField.stringValue = shortcut.name
        enabledButton.state = shortcut.isEnabled ? .on : .off
        globalButton.state = shortcut.isGlobal ? .on : .off
        keyRecorder.setShortcut(keyCode: shortcut.keyCode, modifiers: shortcut.cocoaModifiers)
        detailFields["rows"]?.integerValue = shortcut.rows
        detailFields["columns"]?.integerValue = shortcut.columns
        detailFields["startRow"]?.integerValue = shortcut.selection.startRow
        detailFields["startColumn"]?.integerValue = shortcut.selection.startColumn
        detailFields["endRow"]?.integerValue = shortcut.selection.endRow
        detailFields["endColumn"]?.integerValue = shortcut.selection.endColumn
    }

    @objc private func toggleShortcut(_ sender: NSButton) {
        guard shortcuts.indices.contains(sender.tag) else { return }
        var proposed = shortcuts
        proposed[sender.tag].isEnabled = sender.state == .on
        if !persistAndReload(proposed, selectedRow: sender.tag) {
            sender.state = shortcuts[sender.tag].isEnabled ? .on : .off
        }
    }

    @objc private func saveEditor() {
        let row = table.selectedRow
        guard shortcuts.indices.contains(row) else { return }
        var shortcut = shortcuts[row]
        shortcut.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if shortcut.name.isEmpty { shortcut.name = "Shortcut" }
        shortcut.isEnabled = enabledButton.state == .on
        shortcut.isGlobal = globalButton.state == .on
        shortcut.rows = clamped(detailFields["rows"]?.integerValue ?? shortcut.rows, 1...20)
        shortcut.columns = clamped(detailFields["columns"]?.integerValue ?? shortcut.columns, 1...20)
        let rowLimit = shortcut.rows * (shortcut.isSubdivided ? 2 : 1) - 1
        let columnLimit = shortcut.columns * (shortcut.isSubdivided ? 2 : 1) - 1
        let startRow = clamped(detailFields["startRow"]?.integerValue ?? shortcut.selection.startRow, 0...rowLimit)
        let startColumn = clamped(detailFields["startColumn"]?.integerValue ?? shortcut.selection.startColumn, 0...columnLimit)
        let endRow = clamped(detailFields["endRow"]?.integerValue ?? shortcut.selection.endRow, 0...rowLimit)
        let endColumn = clamped(detailFields["endColumn"]?.integerValue ?? shortcut.selection.endColumn, 0...columnLimit)
        shortcut.selection = GridSelection(startRow: startRow, startColumn: startColumn, endRow: endRow, endColumn: endColumn)
        var proposed = shortcuts
        proposed[row] = shortcut
        _ = persistAndReload(proposed, selectedRow: row)
    }

    func controlTextDidEndEditing(_ notification: Notification) { saveEditor() }

    @discardableResult
    private func persistAndReload(_ proposed: [WindowShortcut], selectedRow: Int? = nil) -> Bool {
        do {
            try store.replaceShortcuts(proposed, panel: AppPreferences.shared.panelShortcut)
        } catch {
            present(error)
            refreshEditor()
            return false
        }
        shortcuts = proposed
        NotificationCenter.default.post(name: AppPreferences.shortcutsDidChangeNotification, object: store)
        table.reloadData()
        let row = selectedRow ?? table.selectedRow
        if shortcuts.indices.contains(row) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        refreshEditor()
        return true
    }

    @objc private func exportShortcuts() {
        ShortcutFileImporter.exportShortcuts(store: store, window: view.window)
    }

    @objc private func importShortcuts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ShortcutFileImporter.openableTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Pane shortcuts file to import."
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            // Defer so the open panel's sheet is fully dismissed before the next sheet.
            DispatchQueue.main.async {
                ShortcutFileImporter.importFile(at: url, store: self.store, window: self.view.window)
            }
        }
    }

    // Imports can also arrive from Finder (double-clicking a .paneshortcuts file) while this
    // window is open; reload whenever the stored list no longer matches what is shown.
    @objc private func storedShortcutsDidChange(_ notification: Notification) {
        let stored = store.shortcuts
        guard stored != shortcuts else { return }
        shortcuts = stored
        table.reloadData()
        if !shortcuts.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        refreshEditor()
    }

    private func present(_ error: Error) {
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}

private final class ShortcutMiniGridView: NSView {
    private let shortcut: WindowShortcut

    init(shortcut: WindowShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 40))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let multiplier = shortcut.isSubdivided ? 2 : 1
        let rows = max(1, shortcut.rows * multiplier)
        let columns = max(1, shortcut.columns * multiplier)
        let width = min(bounds.width, 120) / CGFloat(columns)
        let height = min(bounds.height, 38) / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let selected = row >= shortcut.selection.startRow && row <= shortcut.selection.endRow && column >= shortcut.selection.startColumn && column <= shortcut.selection.endColumn
                (selected ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
                let rect = NSRect(x: CGFloat(column) * width + 0.5,
                                  y: CGFloat(rows - row - 1) * height + 0.5,
                                  width: max(1, width - 1), height: max(1, height - 1))
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
        }
    }
}

private final class ShortcutEditorWindowController: NSWindowController, NSTextFieldDelegate {
    var onSave: ((WindowShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private var draft: WindowShortcut
    private let otherShortcuts: [WindowShortcut]
    private let nameField = NSTextField()
    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let globalButton = NSButton(checkboxWithTitle: "Global shortcut", target: nil, action: nil)
    private let subdividedButton = NSButton(checkboxWithTitle: "Use subdivided grid", target: nil, action: nil)
    private let rowsField = NSTextField()
    private let columnsField = NSTextField()
    private let recorder = ShortcutRecorderButton()
    private let gridSelector = ShortcutGridSelectionView()

    init(shortcut: WindowShortcut, otherShortcuts: [WindowShortcut]) {
        draft = shortcut
        self.otherShortcuts = otherShortcuts
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Shortcut"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 24
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.widthAnchor.constraint(equalToConstant: 250).isActive = true
        form.addArrangedSubview(sectionTitle("Shortcut Details"))
        form.addArrangedSubview(label("Name"))
        nameField.stringValue = draft.name
        nameField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        form.addArrangedSubview(nameField)
        enabledButton.state = draft.isEnabled ? .on : .off
        form.addArrangedSubview(enabledButton)
        globalButton.state = draft.isGlobal ? .on : .off
        form.addArrangedSubview(globalButton)
        let scopeNote = NSTextField(wrappingLabelWithString: "Non-global shortcuts are saved but are not registered in this menu-bar app.")
        scopeNote.textColor = .secondaryLabelColor
        scopeNote.maximumNumberOfLines = 2
        form.addArrangedSubview(scopeNote)

        form.addArrangedSubview(label("Keyboard shortcut"))
        recorder.setShortcut(keyCode: draft.keyCode, modifiers: draft.cocoaModifiers)
        recorder.onChange = { [weak self] keyCode, modifiers in
            self?.draft.keyCode = keyCode
            self?.draft.cocoaModifiers = modifiers
        }
        form.addArrangedSubview(recorder)

        form.addArrangedSubview(separator(width: 250))
        form.addArrangedSubview(sectionTitle("Grid Size"))
        let dimensions = NSStackView()
        dimensions.orientation = .horizontal
        dimensions.spacing = 8
        dimensions.addArrangedSubview(label("Rows"))
        configureDimensionField(rowsField, value: draft.rows)
        dimensions.addArrangedSubview(rowsField)
        dimensions.addArrangedSubview(label("Columns"))
        configureDimensionField(columnsField, value: draft.columns)
        dimensions.addArrangedSubview(columnsField)
        form.addArrangedSubview(dimensions)
        subdividedButton.state = draft.isSubdivided ? .on : .off
        subdividedButton.target = self
        subdividedButton.action = #selector(dimensionsChanged)
        form.addArrangedSubview(subdividedButton)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(button("Cancel", target: self, action: #selector(cancel)))
        let save = button("Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(save)
        form.addArrangedSubview(buttons)
        root.addArrangedSubview(form)

        let preview = NSStackView()
        preview.orientation = .vertical
        preview.alignment = .leading
        preview.spacing = 10
        preview.addArrangedSubview(sectionTitle("Drag to choose the window area"))
        gridSelector.rows = draft.rows
        gridSelector.columns = draft.columns
        gridSelector.isSubdivided = draft.isSubdivided
        gridSelector.selection = draft.selection
        gridSelector.onSelectionChanged = { [weak self] selection in self?.draft.selection = selection }
        gridSelector.widthAnchor.constraint(equalToConstant: 290).isActive = true
        gridSelector.heightAnchor.constraint(equalToConstant: 360).isActive = true
        preview.addArrangedSubview(gridSelector)
        let hint = NSTextField(wrappingLabelWithString: "The highlighted cells show where Pane will place the frontmost window.")
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        preview.addArrangedSubview(hint)
        root.addArrangedSubview(preview)
    }

    private func configureDimensionField(_ field: NSTextField, value: Int) {
        field.integerValue = value
        field.alignment = .right
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true
    }

    func controlTextDidEndEditing(_ notification: Notification) { dimensionsChanged() }

    @objc private func dimensionsChanged() {
        draft.rows = clamped(rowsField.integerValue, 1...20)
        draft.columns = clamped(columnsField.integerValue, 1...20)
        draft.isSubdivided = subdividedButton.state == .on
        rowsField.integerValue = draft.rows
        columnsField.integerValue = draft.columns
        gridSelector.rows = draft.rows
        gridSelector.columns = draft.columns
        gridSelector.isSubdivided = draft.isSubdivided
        draft.selection = gridSelector.selection
    }

    @objc private func save() {
        window?.makeFirstResponder(nil)
        dimensionsChanged()
        draft.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.isEnabled = enabledButton.state == .on
        draft.isGlobal = globalButton.state == .on
        guard !draft.name.isEmpty else { showValidation("Enter a name for this shortcut."); return }
        do {
            try ShortcutConflictValidator.validate(otherShortcuts + [draft], panel: AppPreferences.shared.panelShortcut)
        } catch {
            showValidation(error.localizedDescription)
            return
        }
        onSave?(draft)
    }

    @objc private func cancel() { onCancel?() }

    private func showValidation(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot Save Shortcut"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) }
    }
}

private final class ShortcutGridSelectionView: NSView {
    var rows = 10 { didSet { normalizeSelection(); needsDisplay = true } }
    var columns = 10 { didSet { normalizeSelection(); needsDisplay = true } }
    var isSubdivided = false { didSet { normalizeSelection(); needsDisplay = true } }
    var selection = GridSelection(startRow: 0, startColumn: 0, endRow: 9, endColumn: 9) {
        didSet { needsDisplay = true }
    }
    var onSelectionChanged: ((GridSelection) -> Void)?
    private var anchor: (row: Int, column: Int)?

    private var effectiveRows: Int { max(1, rows * (isSubdivided ? 2 : 1)) }
    private var effectiveColumns: Int { max(1, columns * (isSubdivided ? 2 : 1)) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let hGap: CGFloat = effectiveColumns > 12 ? 1.5 : 3
        let vGap: CGFloat = effectiveRows > 12 ? 1.5 : 3
        for row in 0..<effectiveRows {
            for column in 0..<effectiveColumns {
                let rect = cellRect(row: row, column: column).insetBy(dx: hGap / 2, dy: vGap / 2)
                let selected = row >= selection.startRow && row <= selection.endRow && column >= selection.startColumn && column <= selection.endColumn
                (selected ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = cell(at: convert(event.locationInWindow, from: nil))
        anchor = location
        setSelection(to: location)
    }

    override func mouseDragged(with event: NSEvent) {
        setSelection(to: cell(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        setSelection(to: cell(at: convert(event.locationInWindow, from: nil)))
        anchor = nil
    }

    private func setSelection(to point: (row: Int, column: Int)) {
        guard let anchor else { return }
        selection = GridSelection(startRow: anchor.row, startColumn: anchor.column, endRow: point.row, endColumn: point.column)
        onSelectionChanged?(selection)
    }

    private func normalizeSelection() {
        let rowMax = effectiveRows - 1
        let columnMax = effectiveColumns - 1
        selection = GridSelection(
            startRow: clamped(selection.startRow, 0...rowMax),
            startColumn: clamped(selection.startColumn, 0...columnMax),
            endRow: clamped(selection.endRow, 0...rowMax),
            endColumn: clamped(selection.endColumn, 0...columnMax)
        )
        onSelectionChanged?(selection)
    }

    private func cell(at point: CGPoint) -> (row: Int, column: Int) {
        let column = clamped(Int(point.x / max(1, bounds.width) * CGFloat(effectiveColumns)), 0...(effectiveColumns - 1))
        let fromBottom = clamped(Int(point.y / max(1, bounds.height) * CGFloat(effectiveRows)), 0...(effectiveRows - 1))
        return (effectiveRows - fromBottom - 1, column)
    }

    private func cellRect(row: Int, column: Int) -> CGRect {
        let width = bounds.width / CGFloat(effectiveColumns)
        let height = bounds.height / CGFloat(effectiveRows)
        return CGRect(x: CGFloat(column) * width, y: CGFloat(effectiveRows - row - 1) * height, width: width, height: height)
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onChange: ((UInt32, UInt) -> Void)?
    private(set) var keyCode: UInt32 = UInt32(kVK_Space)
    private(set) var modifiers: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue
    private var isRecording = false

    convenience init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue) {
        self.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        setShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    override var acceptsFirstResponder: Bool { true }

    func setShortcut(keyCode: UInt32, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        title = shortcutDisplay(keyCode: keyCode, modifiers: modifiers)
        toolTip = "Click, then press a key combination"
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = "Type shortcut…"
        NotificationCenter.default.post(name: AppPreferences.hotKeyRecordingDidBeginNotification, object: self)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            setShortcut(keyCode: keyCode, modifiers: modifiers)
            NotificationCenter.default.post(name: AppPreferences.hotKeyRecordingDidEndNotification, object: self)
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { NSSound.beep(); return }
        isRecording = false
        setShortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue)
        NotificationCenter.default.post(name: AppPreferences.hotKeyRecordingDidEndNotification, object: self)
        onChange?(keyCode, modifiers)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            setShortcut(keyCode: keyCode, modifiers: modifiers)
            NotificationCenter.default.post(name: AppPreferences.hotKeyRecordingDidEndNotification, object: self)
        }
        return super.resignFirstResponder()
    }
}

private func shortcutDisplay(keyCode: UInt32, modifiers: UInt) -> String {
    let flags = NSEvent.ModifierFlags(rawValue: modifiers)
    var result = ""
    if flags.contains(.control) { result += "⌃" }
    if flags.contains(.option) { result += "⌥" }
    if flags.contains(.shift) { result += "⇧" }
    if flags.contains(.command) { result += "⌘" }
    let names: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]
    return result + (names[keyCode] ?? keyboardLayoutName(for: keyCode) ?? "Key \(keyCode)")
}

/// The character a key code types on the current keyboard layout (e.g. 46 → "M").
private func keyboardLayoutName(for keyCode: UInt32) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
        guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
        return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                              UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                              &deadKeyState, chars.count, &length, &chars)
    }
    guard status == noErr, length > 0 else { return nil }
    let text = String(utf16CodeUnits: chars, count: length)
        .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return text.isEmpty ? nil : text
}

private func verticalStack(in view: NSView) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
        stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
        stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 26)
    ])
    return stack
}

private func sectionTitle(_ title: String) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.font = .boldSystemFont(ofSize: 15)
    return field
}

private func label(_ title: String) -> NSTextField { NSTextField(labelWithString: title) }

private func checkbox(_ title: String, state: Bool, target: AnyObject, action: Selector) -> NSButton {
    let control = NSButton(checkboxWithTitle: title, target: target, action: action)
    control.state = state ? .on : .off
    return control
}

private func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    NSButton(title: title, target: target, action: action)
}

private func separator(width: CGFloat = 620) -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
    return box
}

private func clamped(_ value: Int, _ range: ClosedRange<Int>) -> Int {
    min(range.upperBound, max(range.lowerBound, value))
}
