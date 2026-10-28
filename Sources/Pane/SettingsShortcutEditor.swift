import AppKit
import Carbon
import PaneCore

/// The New/Edit Shortcut sheet: a form on the left, a drag-to-select grid on the right,
/// Cancel and Save (default) at the bottom right.
final class ShortcutEditorWindowController: NSWindowController {
    var onSave: ((WindowShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private var draft: WindowShortcut
    private let otherShortcuts: [WindowShortcut]
    private let nameField = NSTextField()
    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let globalButton = NSButton(checkboxWithTitle: "Global shortcut", target: nil, action: nil)
    private let subdividedButton = NSButton(checkboxWithTitle: "Use subdivided grid", target: nil, action: nil)
    private var rowsField: NumberStepperField!
    private var columnsField: NumberStepperField!
    private let recorder = ShortcutRecorderButton()
    private let gridSelector = ShortcutGridSelectionView()

    init(shortcut: WindowShortcut, otherShortcuts: [WindowShortcut]) {
        draft = shortcut
        self.otherShortcuts = otherShortcuts
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Shortcut"
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
        nameField.placeholderString = "Shortcut name"
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        form.addRow(with: [formLabel("Name:"), nameField])

        recorder.setShortcut(keyCode: draft.keyCode, modifiers: draft.cocoaModifiers)
        recorder.onChange = { [weak self] keyCode, modifiers in
            self?.draft.keyCode = keyCode
            self?.draft.cocoaModifiers = modifiers
        }
        form.addRow(with: [formLabel("Shortcut:"), recorder])

        enabledButton.state = draft.isEnabled ? .on : .off
        globalButton.state = draft.isGlobal ? .on : .off
        form.addRow(with: [formLabel("Options:"), enabledButton]).topPadding = 8
        form.addRow(with: [NSGridCell.emptyContentView, globalButton])
        form.addRow(with: [NSGridCell.emptyContentView,
                           wrappingNote("Non-global shortcuts are saved but not registered in this menu-bar app.", width: 200)])

        rowsField = NumberStepperField(value: Double(draft.rows), range: 1...20, width: 40)
        columnsField = NumberStepperField(value: Double(draft.columns), range: 1...20, width: 40)
        rowsField.onChange = { [weak self] _ in self?.dimensionsChanged() }
        columnsField.onChange = { [weak self] _ in self?.dimensionsChanged() }
        form.addRow(with: [formLabel("Rows:"), rowsField]).topPadding = 8
        form.addRow(with: [formLabel("Columns:"), columnsField])
        subdividedButton.state = draft.isSubdivided ? .on : .off
        subdividedButton.target = self
        subdividedButton.action = #selector(dimensionsChanged)
        form.addRow(with: [NSGridCell.emptyContentView, subdividedButton])

        gridSelector.rows = draft.rows
        gridSelector.columns = draft.columns
        gridSelector.isSubdivided = draft.isSubdivided
        gridSelector.selection = draft.selection
        gridSelector.onSelectionChanged = { [weak self] selection in self?.draft.selection = selection }
        gridSelector.translatesAutoresizingMaskIntoConstraints = false
        gridSelector.widthAnchor.constraint(equalToConstant: 288).isActive = true
        gridSelector.heightAnchor.constraint(equalToConstant: 192).isActive = true
        gridSelector.setAccessibilityLabel("Window area")
        let hint = wrappingNote("Drag across the grid to choose where Pane places the frontmost window.", width: 288)
        let preview = NSStackView(views: [gridSelector, hint])
        preview.orientation = .vertical
        preview.alignment = .leading
        preview.spacing = SettingsMetrics.spacing

        let columns = NSStackView(views: [form, preview])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = m

        let cancel = pushButton("Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = pushButton("Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        [cancel, save].forEach { $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true }
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = SettingsMetrics.spacing
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
        window.setContentSize(root.fittingSize.padded(by: m))
        window.defaultButtonCell = save.cell as? NSButtonCell
        window.initialFirstResponder = nil
    }

    @objc private func dimensionsChanged() {
        draft.rows = clamped(Int(rowsField.doubleValue), 1...20)
        draft.columns = clamped(Int(columnsField.doubleValue), 1...20)
        draft.isSubdivided = subdividedButton.state == .on
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

private extension NSSize {
    func padded(by margin: CGFloat) -> NSSize { NSSize(width: width + margin * 2, height: height + margin * 2) }
}

/// Drag-to-select grid in the editor sheet.
final class ShortcutGridSelectionView: NSView {
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
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        frame.fill()
        NSColor.separatorColor.setStroke()
        frame.stroke()
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

    private var inset: NSRect { bounds.insetBy(dx: 6, dy: 6) }

    private func cell(at point: CGPoint) -> (row: Int, column: Int) {
        let area = inset
        let column = clamped(Int((point.x - area.minX) / max(1, area.width) * CGFloat(effectiveColumns)), 0...(effectiveColumns - 1))
        let fromBottom = clamped(Int((point.y - area.minY) / max(1, area.height) * CGFloat(effectiveRows)), 0...(effectiveRows - 1))
        return (effectiveRows - fromBottom - 1, column)
    }

    private func cellRect(row: Int, column: Int) -> CGRect {
        let area = inset
        let width = area.width / CGFloat(effectiveColumns)
        let height = area.height / CGFloat(effectiveRows)
        return CGRect(x: area.minX + CGFloat(column) * width,
                      y: area.minY + CGFloat(effectiveRows - row - 1) * height,
                      width: width, height: height)
    }
}

/// A push button that records a key combination when clicked. Posts the recording
/// notifications so global hotkeys are suspended while recording.
final class ShortcutRecorderButton: NSButton {
    var onChange: ((UInt32, UInt) -> Void)?
    private(set) var keyCode: UInt32 = UInt32(kVK_Space)
    private(set) var modifiers: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue
    private var isRecording = false

    // `ShortcutRecorderButton()` goes through init(frame:), so configure there.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        setShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    convenience init(keyCode: UInt32, modifiers: UInt) {
        self.init(frame: .zero)
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

    // While recording, take every key (including Return/Escape) before the window's
    // default and cancel buttons see them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
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

func shortcutDisplay(keyCode: UInt32, modifiers: UInt) -> String {
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
