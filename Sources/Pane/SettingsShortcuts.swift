import AppKit
import Carbon
import PaneCore

/// Shortcuts tab: a System Settings-style list in a rounded box with a +/− and action-menu
/// footer attached to its bottom edge.
final class ShortcutsPreferencesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    private let store = ShortcutStore.shared
    private var shortcuts: [WindowShortcut] = []
    private let table = ShortcutsTableView()
    private let removeButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No Shortcuts — click + to add one.")
    private let registrationStatus = NSTextField(labelWithString: "")
    private var activeEditor: ShortcutEditorWindowController?

    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let shortcut = NSUserInterfaceItemIdentifier("shortcut")
        static let placement = NSUserInterfaceItemIdentifier("placement")
    }

    override func loadView() {
        let size = NSSize(width: SettingsMetrics.windowWidth, height: 460)
        view = NSView(frame: NSRect(origin: .zero, size: size))
        preferredContentSize = size
        shortcuts = store.shortcuts

        let box = NSBox()
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.contentViewMargins = .zero
        box.titlePosition = .noTitle
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)

        // Clip the table to the box's rounded corners.
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 7
        clip.layer?.masksToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(clip)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        buildTable()
        scroll.documentView = table

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        let footer = buildFooter()

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        [scroll, divider, footer, emptyLabel].forEach(clip.addSubview)
        let m = SettingsMetrics.margin
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            box.topAnchor.constraint(equalTo: view.topAnchor, constant: m),
            box.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -m),

            clip.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 1),
            clip.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -1),
            clip.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
            clip.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1),

            scroll.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: clip.topAnchor),
            divider.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            divider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor),
            footer.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])

        table.reloadData()
        if !shortcuts.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateState()
        NotificationCenter.default.addObserver(self, selector: #selector(showRegistrationFailures(_:)), name: AppPreferences.hotKeyRegistrationFailuresNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storedShortcutsDidChange(_:)), name: AppPreferences.shortcutsDidChangeNotification, object: nil)
    }

    private func buildTable() {
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat, Bool)] = [
            (Column.enabled, "", 28, false),
            (Column.name, "Name", 240, true),
            (Column.shortcut, "Shortcut", 110, false),
            (Column.placement, "Placement", 120, false)
        ]
        for (id, title, width, flexible) in columns {
            let column = NSTableColumn(identifier: id)
            column.title = title
            column.width = width
            column.minWidth = flexible ? 120 : width
            column.resizingMask = flexible ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        table.tableColumns.first?.headerToolTip = "Enabled"
        if #available(macOS 11.0, *) { table.style = .fullWidth }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.rowHeight = 32
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(editShortcut)
        table.onDelete = { [weak self] in self?.deleteShortcut() }
        table.onReturn = { [weak self] in self?.editShortcut() }

        let menu = NSMenu()
        menu.addItem(withTitle: "Edit…", action: #selector(editShortcut), keyEquivalent: "")
        menu.addItem(withTitle: "Delete…", action: #selector(deleteShortcut), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        table.menu = menu
    }

    private func buildFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let add = footerButton(NSImage(named: NSImage.addTemplateName), label: "Add Shortcut", action: #selector(newShortcut))
        configureFooterButton(removeButton, image: NSImage(named: NSImage.removeTemplateName),
                              label: "Delete Shortcut", action: #selector(deleteShortcut))

        let actions = NSPopUpButton(frame: .zero, pullsDown: true)
        actions.isBordered = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        (actions.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        actions.imagePosition = .imageOnly
        let iconItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        iconItem.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More Actions")
            ?? NSImage(named: NSImage.actionTemplateName)
        actions.menu?.addItem(iconItem)
        for (title, selector) in [("Edit…", #selector(editShortcut)),
                                  ("Import Shortcuts…", #selector(importShortcuts)),
                                  ("Export Shortcuts…", #selector(exportShortcuts))] {
            if title == "Import Shortcuts…" { actions.menu?.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            actions.menu?.addItem(item)
        }
        actions.toolTip = "Edit, import, or export shortcuts"
        actions.setAccessibilityLabel("More Actions")

        registrationStatus.textColor = .systemRed
        registrationStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        registrationStatus.lineBreakMode = .byTruncatingTail
        registrationStatus.translatesAutoresizingMaskIntoConstraints = false
        registrationStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        [add, removeButton, actions, registrationStatus].forEach(footer.addSubview)
        NSLayoutConstraint.activate([
            add.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 4),
            add.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: add.trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            actions.leadingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 4),
            actions.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            actions.widthAnchor.constraint(equalToConstant: 30),
            registrationStatus.leadingAnchor.constraint(greaterThanOrEqualTo: actions.trailingAnchor, constant: SettingsMetrics.spacing),
            registrationStatus.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
            registrationStatus.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        return footer
    }

    private func footerButton(_ image: NSImage?, label: String, action: Selector) -> NSButton {
        let button = NSButton()
        configureFooterButton(button, image: image, label: label, action: action)
        return button
    }

    private func configureFooterButton(_ button: NSButton, image: NSImage?, label: String, action: Selector) {
        button.image = image
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { shortcuts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let shortcut = shortcuts[row]
        let grid = "\(shortcut.columns)×\(shortcut.rows)\(shortcut.isSubdivided ? " (subdivided)" : "")"
        let tooltip = "\(shortcut.name) — \(shortcut.isGlobal ? "global shortcut" : "saved, not registered globally"), \(grid) grid"
        switch id {
        case Column.enabled:
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleShortcut(_:)))
            box.state = shortcut.isEnabled ? .on : .off
            box.tag = row
            box.toolTip = shortcut.isEnabled ? "Enabled" : "Disabled"
            box.setAccessibilityLabel("Enable \(shortcut.name)")
            return centered(box)
        case Column.placement:
            let thumbnail = ShortcutThumbnailView(shortcut: shortcut)
            thumbnail.toolTip = "Rows \(shortcut.selection.startRow + 1)–\(shortcut.selection.endRow + 1), columns \(shortcut.selection.startColumn + 1)–\(shortcut.selection.endColumn + 1) of a \(grid) grid"
            let size = secondaryLabel("\(shortcut.columns)×\(shortcut.rows)", small: true)
            size.toolTip = thumbnail.toolTip
            let stack = hStack([thumbnail, size])
            stack.alignment = .centerY
            return centered(stack, leading: true)
        default:
            let value = id == Column.name
                ? shortcut.name
                : shortcutDisplay(keyCode: shortcut.keyCode, modifiers: shortcut.cocoaModifiers)
            let text = NSTextField(labelWithString: value)
            text.lineBreakMode = .byTruncatingTail
            text.textColor = shortcut.isEnabled ? .labelColor : .secondaryLabelColor
            if id == Column.name && !shortcut.isGlobal {
                let attributed = NSMutableAttributedString(string: value, attributes: [.foregroundColor: text.textColor!])
                attributed.append(NSAttributedString(string: "  Not global", attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                ]))
                text.attributedStringValue = attributed
            }
            text.toolTip = tooltip
            return centered(text, leading: true)
        }
    }

    /// A cell container that vertically centers its content (NSTableView top-aligns by default).
    private func centered(_ content: NSView, leading: Bool = false) -> NSView {
        let cell = NSTableCellView()
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(content)
        var constraints = [content.centerYAnchor.constraint(equalTo: cell.centerYAnchor)]
        if leading {
            constraints += [
                content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                content.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor)
            ]
        } else {
            constraints.append(content.centerXAnchor.constraint(equalTo: cell.centerXAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        if let text = content as? NSTextField { cell.textField = text }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateState() }

    private func updateState() {
        removeButton.isEnabled = shortcuts.indices.contains(table.selectedRow)
        emptyLabel.isHidden = !shortcuts.isEmpty
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(editShortcut), #selector(deleteShortcut): return shortcuts.indices.contains(targetRow)
        case #selector(exportShortcuts): return !shortcuts.isEmpty
        default: return true
        }
    }

    /// The row a command applies to: the right-clicked or double-clicked row, else the selection.
    private var targetRow: Int { table.clickedRow >= 0 ? table.clickedRow : table.selectedRow }

    // MARK: Actions

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
        let row = targetRow
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
        child.makeFirstResponder(nil)
    }

    @objc private func deleteShortcut() {
        let row = targetRow
        guard shortcuts.indices.contains(row), let window = view.window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(shortcuts[row].name)”?"
        alert.informativeText = "This removes the shortcut from Pane. This action cannot be undone after the settings window is closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if #available(macOS 11.0, *) { alert.buttons.first?.hasDestructiveAction = true }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var proposed = self.shortcuts
            proposed.remove(at: row)
            _ = self.persistAndReload(proposed, selectedRow: proposed.isEmpty ? nil : min(row, proposed.count - 1))
        }
    }

    @objc private func toggleShortcut(_ sender: NSButton) {
        guard shortcuts.indices.contains(sender.tag) else { return }
        var proposed = shortcuts
        proposed[sender.tag].isEnabled = sender.state == .on
        if !persistAndReload(proposed, selectedRow: table.selectedRow) {
            sender.state = shortcuts[sender.tag].isEnabled ? .on : .off
        }
    }

    @objc private func showRegistrationFailures(_ notification: Notification) {
        let failures = notification.object as? [String] ?? []
        registrationStatus.stringValue = failures.isEmpty ? "" : "⚠︎ Could not register: \(failures.joined(separator: ", "))"
        registrationStatus.toolTip = registrationStatus.stringValue
    }

    @discardableResult
    private func persistAndReload(_ proposed: [WindowShortcut], selectedRow: Int? = nil) -> Bool {
        do {
            try store.replaceShortcuts(proposed, panel: AppPreferences.shared.panelShortcut)
        } catch {
            present(error)
            return false
        }
        shortcuts = proposed
        NotificationCenter.default.post(name: AppPreferences.shortcutsDidChangeNotification, object: store)
        table.reloadData()
        let row = selectedRow ?? table.selectedRow
        if shortcuts.indices.contains(row) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        updateState()
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
        updateState()
    }

    private func present(_ error: Error) {
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}

/// Adds Delete (remove) and Return (edit) keys to the shortcut list.
final class ShortcutsTableView: NSTableView {
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let key = Int(event.keyCode)
        if selectedRow >= 0, key == kVK_Delete || key == kVK_ForwardDelete {
            onDelete?()
        } else if selectedRow >= 0, key == kVK_Return || key == kVK_ANSI_KeypadEnter {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// A small screen-shaped thumbnail with the shortcut's target area in the accent color.
final class ShortcutThumbnailView: NSView {
    private let shortcut: WindowShortcut
    static let size = NSSize(width: 44, height: 26)

    init(shortcut: WindowShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let screen = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath(roundedRect: screen, xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        outline.fill()
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let multiplier = shortcut.isSubdivided ? 2 : 1
        let rows = CGFloat(max(1, shortcut.rows * multiplier))
        let columns = CGFloat(max(1, shortcut.columns * multiplier))
        let sel = shortcut.selection
        let inner = bounds.insetBy(dx: 3, dy: 3)
        let cellW = inner.width / columns, cellH = inner.height / rows
        let area = NSRect(x: inner.minX + CGFloat(min(sel.startColumn, sel.endColumn)) * cellW,
                          y: inner.minY + CGFloat(min(sel.startRow, sel.endRow)) * cellH,
                          width: CGFloat(abs(sel.endColumn - sel.startColumn) + 1) * cellW,
                          height: CGFloat(abs(sel.endRow - sel.startRow) + 1) * cellH)
        let accent = NSColor.controlAccentColor.withAlphaComponent(shortcut.isEnabled ? 1 : 0.4)
        accent.setFill()
        NSBezierPath(roundedRect: area, xRadius: 2, yRadius: 2).fill()
    }
}
