import AppKit
import PaneCore

/// Displays tab: the on/off switch for display arrangement, then the saved layouts in the
/// same rounded list box as the Shortcuts tab, with a +/− and action-menu footer.
final class DisplaysPreferencesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    private let store = DisplayLayoutStore.shared
    private var layouts: [DisplayLayout] = []
    private let table = ShortcutsTableView()
    private let removeButton = NSButton()
    private var enabledButton: NSButton!
    private let emptyLabel = NSTextField(labelWithString: "No Layouts — click + to add one.")
    private var activeEditor: DisplayLayoutEditorWindowController?

    private static let rowHeight: CGFloat = 44
    /// Four keys means at most four layouts, so the list always shows every row.
    private static let visibleRows = DoubleTapKey.allCases.count

    private enum Column {
        static let preview = NSUserInterfaceItemIdentifier("preview")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let trigger = NSUserInterfaceItemIdentifier("trigger")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: SettingsMetrics.windowWidth, height: 340)))
        layouts = store.layouts

        enabledButton = checkbox("Arrange displays when a monitor is connected", state: store.isEnabled,
                                 target: self, action: #selector(toggleEnabled))
        enabledButton.translatesAutoresizingMaskIntoConstraints = false
        let note = NSTextField(wrappingLabelWithString: "After you plug in a monitor, double-tap a key within 1 minute to choose a layout.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.contentViewMargins = .zero
        box.titlePosition = .noTitle
        box.translatesAutoresizingMaskIntoConstraints = false

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
        let headerHeight = table.headerView?.frame.height ?? 28

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        let footer = buildFooter()

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        [enabledButton, note, box].forEach(view.addSubview)
        [scroll, divider, footer, emptyLabel].forEach(clip.addSubview)
        let m = SettingsMetrics.margin
        NSLayoutConstraint.activate([
            enabledButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            enabledButton.topAnchor.constraint(equalTo: view.topAnchor, constant: m),
            // Line the note up with the checkbox title, not the box.
            note.leadingAnchor.constraint(equalTo: enabledButton.leadingAnchor, constant: checkboxTitleInset),
            note.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -m),
            note.topAnchor.constraint(equalTo: enabledButton.bottomAnchor, constant: 2),

            box.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            box.topAnchor.constraint(equalTo: note.bottomAnchor, constant: m),
            box.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -m),

            clip.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 1),
            clip.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -1),
            clip.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
            clip.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1),

            scroll.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: clip.topAnchor),
            scroll.heightAnchor.constraint(equalToConstant: headerHeight + Self.rowHeight * CGFloat(Self.visibleRows)),
            divider.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            divider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor),
            footer.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: headerHeight / 2)
        ])

        view.widthAnchor.constraint(equalToConstant: SettingsMetrics.windowWidth).isActive = true
        let size = NSSize(width: SettingsMetrics.windowWidth, height: ceil(view.fittingSize.height))
        view.frame = NSRect(origin: .zero, size: size)
        preferredContentSize = size

        table.reloadData()
        if !layouts.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateState()
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)),
                                               name: DisplayLayoutStore.didChangeNotification, object: nil)
    }

    /// Distance from a checkbox's leading edge to its title.
    private var checkboxTitleInset: CGFloat {
        guard let cell = enabledButton.cell as? NSButtonCell else { return 20 }
        let bounds = NSRect(origin: .zero, size: enabledButton.fittingSize)
        return ceil(cell.titleRect(forBounds: bounds).minX)
    }

    private func buildTable() {
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat, Bool)] = [
            (Column.preview, "", 64, false),
            (Column.name, "Layout", 300, true),
            (Column.trigger, "Double-tap", 110, false)
        ]
        for (id, title, width, flexible) in columns {
            let column = NSTableColumn(identifier: id)
            column.title = title
            column.width = width
            column.minWidth = flexible ? 160 : width
            column.resizingMask = flexible ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        if #available(macOS 11.0, *) { table.style = .fullWidth }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(editLayout)
        table.onDelete = { [weak self] in self?.deleteLayout() }
        table.onReturn = { [weak self] in self?.editLayout() }

        let menu = NSMenu()
        for (title, selector) in [("Edit…", #selector(editLayout)), ("Apply Now", #selector(applyLayout)),
                                  ("Delete…", #selector(deleteLayout))] {
            if title == "Delete…" { menu.addItem(.separator()) }
            menu.addItem(withTitle: title, action: selector, keyEquivalent: "").target = self
        }
        table.menu = menu
    }

    private func buildFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let add = NSButton()
        configureFooterButton(add, image: NSImage(named: NSImage.addTemplateName), label: "Add Layout", action: #selector(newLayout))
        configureFooterButton(removeButton, image: NSImage(named: NSImage.removeTemplateName),
                              label: "Delete Layout", action: #selector(deleteLayout))

        let actions = NSPopUpButton(frame: .zero, pullsDown: true)
        actions.isBordered = false
        actions.translatesAutoresizingMaskIntoConstraints = false
        (actions.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        actions.imagePosition = .imageOnly
        let iconItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        iconItem.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More Actions")
            ?? NSImage(named: NSImage.actionTemplateName)
        actions.menu?.addItem(iconItem)
        for (title, selector) in [("Edit…", #selector(editLayout)),
                                  ("Apply Now", #selector(applyLayout)),
                                  ("Restore Default Layouts…", #selector(restoreDefaults))] {
            if title.hasPrefix("Restore") { actions.menu?.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            actions.menu?.addItem(item)
        }
        actions.toolTip = "Edit or apply a layout, or restore the defaults"
        actions.setAccessibilityLabel("More Actions")

        [add, removeButton, actions].forEach(footer.addSubview)
        NSLayoutConstraint.activate([
            add.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 4),
            add.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: add.trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            actions.leadingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 4),
            actions.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            actions.widthAnchor.constraint(equalToConstant: 30)
        ])
        return footer
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

    func numberOfRows(in tableView: NSTableView) -> Int { layouts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let layout = layouts[row]
        let menuBar = "menu bar on the \(layout.menuBar == .mac ? "Mac" : "monitor")"
        switch id {
        case Column.preview:
            let thumbnail = DisplayArrangementView(layout: layout, style: .thumbnail)
            thumbnail.toolTip = "\(layout.summary), \(menuBar)"
            return centered(thumbnail)
        case Column.trigger:
            let text = NSTextField(labelWithString: layout.trigger.symbolPair)
            text.toolTip = "Double-tap \(layout.trigger.displayName)"
            text.setAccessibilityLabel("Double-tap \(layout.trigger.displayName)")
            return centered(text, leading: true)
        default:
            let name = NSTextField(labelWithString: layout.name)
            name.lineBreakMode = .byTruncatingTail
            let summary = secondaryLabel("\(layout.summary) · \(menuBar)", small: true)
            summary.lineBreakMode = .byTruncatingTail
            let stack = NSStackView(views: [name, summary])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 1
            stack.toolTip = "\(layout.name) — \(layout.summary), \(menuBar)"
            let cell = centered(stack, leading: true)
            (cell as? NSTableCellView)?.textField = name
            return cell
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
        removeButton.isEnabled = layouts.indices.contains(table.selectedRow)
        emptyLabel.isHidden = !layouts.isEmpty
        enabledButton.state = store.isEnabled ? .on : .off
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(editLayout), #selector(deleteLayout), #selector(applyLayout): return layouts.indices.contains(targetRow)
        case #selector(restoreDefaults): return layouts != DisplayLayout.defaults
        default: return true
        }
    }

    /// The row a command applies to: the right-clicked or double-clicked row, else the selection.
    private var targetRow: Int { table.clickedRow >= 0 ? table.clickedRow : table.selectedRow }

    // MARK: Actions

    @objc private func toggleEnabled() {
        store.isEnabled = enabledButton.state == .on
    }

    @objc private func newLayout() {
        let used = Set(layouts.map(\.trigger))
        guard let key = DoubleTapKey.allCases.first(where: { !used.contains($0) }) else {
            guard let window = view.window else { return }
            let alert = NSAlert()
            alert.messageText = "All four keys are in use."
            alert.informativeText = "Each layout needs its own key. Delete a layout or change its key to add another."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
            return
        }
        let layout = DisplayLayout(name: "New Layout", trigger: key, position: .right, alignment: .center, menuBar: .mac)
        presentEditor(layout, replacing: nil)
    }

    @objc private func editLayout() {
        let row = targetRow
        guard layouts.indices.contains(row) else { NSSound.beep(); return }
        presentEditor(layouts[row], replacing: row)
    }

    @objc private func applyLayout() {
        let row = targetRow
        guard layouts.indices.contains(row) else { NSSound.beep(); return }
        applyDisplayLayout(layouts[row], presentingIn: view.window)
    }

    private func presentEditor(_ layout: DisplayLayout, replacing index: Int?) {
        guard let parent = view.window else { return }
        let others = layouts.enumerated().compactMap { $0.offset == index ? nil : $0.element }
        let editor = DisplayLayoutEditorWindowController(layout: layout, otherLayouts: others)
        activeEditor = editor
        editor.onSave = { [weak self, weak editor] saved in
            guard let self else { return }
            var proposed = self.layouts
            if let index { proposed[index] = saved } else { proposed.append(saved) }
            try self.persist(proposed, selectedRow: index ?? proposed.count - 1)
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

    @objc private func deleteLayout() {
        let row = targetRow
        guard layouts.indices.contains(row), let window = view.window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(layouts[row].name)”?"
        alert.informativeText = "Double-tapping \(layouts[row].trigger.displayName) will no longer arrange your displays."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if #available(macOS 11.0, *) { alert.buttons.first?.hasDestructiveAction = true }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var proposed = self.layouts
            proposed.remove(at: row)
            self.persistOrAlert(proposed, selectedRow: proposed.isEmpty ? nil : min(row, proposed.count - 1))
        }
    }

    @objc private func restoreDefaults() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Restore the default layouts?"
        alert.informativeText = "Your layouts will be replaced with “Mac on left” (double-tap Option) and “Mac below” (double-tap Command)."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.persistOrAlert(DisplayLayout.defaults, selectedRow: 0)
        }
    }

    private func persist(_ proposed: [DisplayLayout], selectedRow: Int?) throws {
        try store.save(proposed)
        layouts = proposed
        table.reloadData()
        let row = selectedRow ?? table.selectedRow
        if layouts.indices.contains(row) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        updateState()
    }

    private func persistOrAlert(_ proposed: [DisplayLayout], selectedRow: Int?) {
        do {
            try persist(proposed, selectedRow: selectedRow)
        } catch {
            guard let window = view.window else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    // The store can change elsewhere (or the switch can be flipped from another place).
    @objc private func storeDidChange(_ notification: Notification) {
        let stored = store.layouts
        if stored != layouts {
            let selectedID = layouts.indices.contains(table.selectedRow) ? layouts[table.selectedRow].id : nil
            layouts = stored
            table.reloadData()
            let row = stored.firstIndex { $0.id == selectedID } ?? 0
            if layouts.indices.contains(row) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
        updateState()
    }
}
