import AppKit
import PaneCore

/// The New/Edit Layout sheet: a form on the left, a live arrangement preview on the right,
/// Apply Now at the bottom left and Cancel / Save (default) at the bottom right.
final class DisplayLayoutEditorWindowController: NSWindowController {
    /// Persists the edited layout. Throws (e.g. `DisplayLayoutStore.SaveError`) to keep the sheet open.
    var onSave: ((DisplayLayout) throws -> Void)?
    var onCancel: (() -> Void)?

    private var draft: DisplayLayout
    private let otherLayouts: [DisplayLayout]
    private let nameField = NSTextField()
    private let triggerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let alignmentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBarPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let preview: DisplayArrangementView

    private static let positionTitles: [(MacPosition, String)] = [
        (.left, "Left of monitor"), (.right, "Right of monitor"),
        (.above, "Above monitor"), (.below, "Below monitor")
    ]
    private static let menuBarTitles: [(MenuBarLocation, String)] = [(.mac, "On the Mac"), (.monitor, "On the monitor")]

    init(layout: DisplayLayout, otherLayouts: [DisplayLayout]) {
        draft = layout
        self.otherLayouts = otherLayouts
        preview = DisplayArrangementView(layout: layout, style: .preview)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Display Layout"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let window, let content = window.contentView else { return }
        let m = SettingsMetrics.margin

        let form = NSGridView(numberOfColumns: 2, rows: 0)
        form.rowSpacing = SettingsMetrics.spacing
        form.columnSpacing = SettingsMetrics.spacing
        form.rowAlignment = .firstBaseline
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .leading

        nameField.stringValue = draft.name
        nameField.placeholderString = "Layout name"
        form.addRow(with: [formLabel("Name:"), nameField])

        // Keys taken by other layouts stay visible but disabled, naming the layout that uses them.
        triggerPopup.autoenablesItems = false
        for key in DoubleTapKey.allCases {
            let owner = otherLayouts.first { $0.trigger == key }
            let item = NSMenuItem(title: key.displayName, action: nil, keyEquivalent: "")
            item.representedObject = key.rawValue
            if let owner {
                item.isEnabled = false
                item.attributedTitle = attributedTitle(key.displayName, note: "Used by “\(owner.name)”")
            }
            triggerPopup.menu?.addItem(item)
        }
        select(triggerPopup, DoubleTapKey.allCases.firstIndex(of: draft.trigger))
        triggerPopup.target = self
        triggerPopup.action = #selector(fieldsChanged)
        triggerPopup.toolTip = "Double-tap this key within 1 minute of plugging in a monitor"
        form.addRow(with: [formLabel("Double-tap:"), triggerPopup])

        Self.positionTitles.forEach { positionPopup.addItem(withTitle: $0.1) }
        select(positionPopup, Self.positionTitles.firstIndex { $0.0 == draft.position })
        positionPopup.target = self
        positionPopup.action = #selector(positionChanged)
        form.addRow(with: [formLabel("Mac position:"), positionPopup]).topPadding = 12

        alignmentPopup.target = self
        alignmentPopup.action = #selector(fieldsChanged)
        reloadAlignmentTitles()
        form.addRow(with: [formLabel("Alignment:"), alignmentPopup])

        Self.menuBarTitles.forEach { menuBarPopup.addItem(withTitle: $0.1) }
        select(menuBarPopup, Self.menuBarTitles.firstIndex { $0.0 == draft.menuBar })
        menuBarPopup.target = self
        menuBarPopup.action = #selector(fieldsChanged)
        form.addRow(with: [formLabel("Menu bar:"), menuBarPopup])

        let popupWidth = [triggerPopup, positionPopup, alignmentPopup, menuBarPopup]
            .map { $0.fittingSize.width }.max() ?? 160
        // One control width, so the right edges line up.
        for control in [nameField, triggerPopup, positionPopup, alignmentPopup, menuBarPopup] {
            control.widthAnchor.constraint(equalToConstant: max(popupWidth, 160)).isActive = true
        }

        // Pin the form to its natural height; otherwise the grid stretches its rows to the
        // taller preview beside it.
        form.translatesAutoresizingMaskIntoConstraints = false
        form.heightAnchor.constraint(equalToConstant: form.fittingSize.height).isActive = true

        let columns = NSStackView(views: [form, preview])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = m

        let apply = pushButton("Apply Now", target: self, action: #selector(applyNow))
        apply.toolTip = "Arrange the connected monitor this way now, without saving"
        let cancel = pushButton("Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = pushButton("Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        [cancel, save].forEach { $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true }
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = SettingsMetrics.spacing
        buttons.addView(apply, in: .leading)
        buttons.addView(cancel, in: .trailing)
        buttons.addView(save, in: .trailing)

        let root = NSStackView(views: [columns, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = m
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        let fitting = root.fittingSize
        window.setContentSize(NSSize(width: fitting.width + m * 2, height: fitting.height + m * 2))
        window.defaultButtonCell = save.cell as? NSButtonCell
        window.initialFirstResponder = nil
    }

    private func attributedTitle(_ title: String, note: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.disabledControlTextColor])
        text.append(NSAttributedString(string: "  \(note)", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        return text
    }

    private func select(_ popup: NSPopUpButton, _ index: Int?) {
        popup.selectItem(at: index ?? 0)
    }

    private func reloadAlignmentTitles() {
        alignmentPopup.removeAllItems()
        for alignment in LayoutAlignment.allCases {
            alignmentPopup.addItem(withTitle: alignment.label(for: draft.position))
        }
        select(alignmentPopup, LayoutAlignment.allCases.firstIndex(of: draft.alignment))
    }

    /// Reads every field into `draft` and refreshes the preview.
    private func readFields() {
        draft.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw = triggerPopup.selectedItem?.representedObject as? String, let key = DoubleTapKey(rawValue: raw) {
            draft.trigger = key
        }
        draft.position = Self.positionTitles[max(0, positionPopup.indexOfSelectedItem)].0
        draft.alignment = LayoutAlignment.allCases[max(0, alignmentPopup.indexOfSelectedItem)]
        draft.menuBar = Self.menuBarTitles[max(0, menuBarPopup.indexOfSelectedItem)].0
        preview.layout = draft
    }

    @objc private func fieldsChanged() { readFields() }

    @objc private func positionChanged() {
        readFields()
        reloadAlignmentTitles()
    }

    @objc private func applyNow() {
        readFields()
        applyDisplayLayout(draft, presentingIn: window)
    }

    @objc private func save() {
        window?.makeFirstResponder(nil)
        readFields()
        do {
            try onSave?(draft)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot Save Layout"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    @objc private func cancel() { onCancel?() }

    /// Snapshot support: an editor window for `--snapshot-overlay`.
    static func makeWindowForSnapshot() -> NSWindow? {
        let layouts = DisplayLayout.defaults
        let editor = DisplayLayoutEditorWindowController(layout: layouts[0], otherLayouts: Array(layouts.dropFirst()))
        snapshotEditor = editor
        editor.window?.makeFirstResponder(nil)
        return editor.window
    }
    private static var snapshotEditor: DisplayLayoutEditorWindowController?
}

/// Arranges the displays now; shows the reason as an alert sheet when it can't.
func applyDisplayLayout(_ layout: DisplayLayout, presentingIn window: NSWindow?) {
    guard let problem = DisplayArranger.apply(layout).problem else { return }
    let alert = NSAlert()
    alert.messageText = "Couldn’t Arrange Displays"
    alert.informativeText = problem
    alert.addButton(withTitle: "OK")
    if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
}
