import AppKit
import PaneCore

/// The Settings window: a toolbar-style tab view (General, Appearance, Shortcuts, Displays).
/// Each tab sizes itself to its content via `preferredContentSize`, so the window
/// grows and shrinks as the user switches tabs, like System Settings-era panes.
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsMetrics.windowWidth, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pane Settings"
        window.isReleasedWhenClosed = false
        if #available(macOS 11.0, *) { window.toolbarStyle = .preference }

        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        // No crossfade: its transition fights the per-tab window resize below.
        tabs.transitionOptions = []
        tabs.addTabViewItem(Self.tab(GeneralPreferencesViewController(), title: "General", symbol: "gearshape"))
        tabs.addTabViewItem(Self.tab(AppearancePreferencesViewController(), title: "Appearance", symbol: "paintbrush"))
        tabs.addTabViewItem(Self.tab(ShortcutsPreferencesViewController(), title: "Shortcuts", symbol: "keyboard"))
        tabs.addTabViewItem(Self.tab(DisplaysPreferencesViewController(), title: "Displays", symbol: "display.2"))
        window.contentViewController = tabs
        self.init(window: window)
        if let size = tabs.tabViewItems.first?.viewController?.preferredContentSize { window.setContentSize(size) }
        window.center()
    }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if !wasVisible { window?.center() }
    }

    private static func tab(_ controller: NSViewController, title: String, symbol: String) -> NSTabViewItem {
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    /// Snapshot support: a shortcut editor sheet window for `--snapshot-overlay`.
    static func makeEditorWindowForSnapshot() -> NSWindow? {
        let sample = ShortcutStore.shared.shortcuts.first ?? WindowShortcut(
            name: "Left Half", keyCode: 37, cocoaModifiers: NSEvent.ModifierFlags.option.rawValue,
            isGlobal: true, isEnabled: true, rows: 6, columns: 6, isSubdivided: false,
            selection: GridSelection(startRow: 0, startColumn: 0, endRow: 5, endColumn: 2))
        let editor = ShortcutEditorWindowController(shortcut: sample, otherShortcuts: [])
        snapshotEditor = editor
        editor.window?.makeFirstResponder(nil)
        return editor.window
    }
    private static var snapshotEditor: ShortcutEditorWindowController?
}

/// Resizes the window to each tab's `preferredContentSize`, keeping the top edge fixed.
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let size = tabViewItem?.viewController?.preferredContentSize, size != .zero,
              let window = view.window else { return }
        let contentRect = window.contentRect(forFrameRect: window.frame)
        guard contentRect.size != size else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: contentRect.origin, size: size))
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: true, animate: window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

// MARK: - Shared layout

enum SettingsMetrics {
    static let windowWidth: CGFloat = 640
    /// Window edge to content, all sides.
    static let margin: CGFloat = 20
    /// Between related controls.
    static let spacing: CGFloat = 8
    /// Right-aligned label column of form tabs, shared so labels line up across tabs.
    static let labelColumnWidth: CGFloat = 170
    static var controlColumnWidth: CGFloat { windowWidth - margin * 2 - labelColumnWidth - spacing }
}

/// A two-column form (right-aligned labels, left-aligned controls) built on NSGridView,
/// matching the classic macOS preferences layout.
final class SettingsForm {
    let grid: NSGridView

    init() {
        grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = SettingsMetrics.spacing
        grid.columnSpacing = SettingsMetrics.spacing
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = SettingsMetrics.labelColumnWidth
        grid.column(at: 1).xPlacement = .leading
    }

    /// Adds a row. Pass a label only for the first row of a group.
    @discardableResult
    func row(_ title: String?, _ control: NSView) -> NSGridRow {
        let titleView: NSView = title.map { formLabel($0) } ?? NSGridCell.emptyContentView
        return grid.addRow(with: [titleView, control])
    }

    /// A full-width separator between groups, with group spacing above and below.
    func separator() {
        let line = NSBox()
        line.boxType = .separator
        let row = grid.addRow(with: [line])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        row.cell(at: 0).xPlacement = .fill
        row.topPadding = 6
        row.bottomPadding = 6
        row.yPlacement = .center
        row.rowAlignment = .none
    }

    /// Pads the row above the next group (used for spacing without a line).
    func gap(before row: NSGridRow) { row.topPadding = 12 }
}

/// Root view for a form tab: the form pinned to 20 pt margins, an optional footer, and a
/// `preferredContentSize` that fits the content so the tab controller sizes the window.
func makeFormTabView(form: SettingsForm, footer: NSView? = nil, for controller: NSViewController) -> NSView {
    let view = NSView()
    view.addSubview(form.grid)
    var constraints = [
        form.grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsMetrics.margin),
        form.grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -SettingsMetrics.margin),
        form.grid.topAnchor.constraint(equalTo: view.topAnchor, constant: SettingsMetrics.margin)
    ]
    var bottomItem: NSView = form.grid
    if let footer {
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        constraints += [
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsMetrics.margin),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SettingsMetrics.margin),
            footer.topAnchor.constraint(equalTo: form.grid.bottomAnchor, constant: SettingsMetrics.margin + 4)
        ]
        bottomItem = footer
    }
    constraints.append(view.bottomAnchor.constraint(greaterThanOrEqualTo: bottomItem.bottomAnchor, constant: SettingsMetrics.margin))
    NSLayoutConstraint.activate(constraints)

    let height = form.grid.fittingSize.height + (footer.map { $0.fittingSize.height + SettingsMetrics.margin + 4 } ?? 0)
        + SettingsMetrics.margin * 2
    let size = NSSize(width: SettingsMetrics.windowWidth, height: ceil(height))
    view.frame = NSRect(origin: .zero, size: size)
    controller.preferredContentSize = size
    return view
}

// MARK: - Small control factories

func formLabel(_ title: String) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.alignment = .right
    return field
}

func label(_ title: String) -> NSTextField { NSTextField(labelWithString: title) }

func secondaryLabel(_ title: String, small: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.textColor = .secondaryLabelColor
    if small { field.font = .systemFont(ofSize: NSFont.smallSystemFontSize) }
    return field
}

func wrappingNote(_ text: String, width: CGFloat) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.textColor = .secondaryLabelColor
    field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    field.preferredMaxLayoutWidth = width
    field.widthAnchor.constraint(equalToConstant: width).isActive = true
    return field
}

func checkbox(_ title: String, state: Bool, target: AnyObject, action: Selector) -> NSButton {
    let control = NSButton(checkboxWithTitle: title, target: target, action: action)
    control.state = state ? .on : .off
    return control
}

func pushButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    NSButton(title: title, target: target, action: action)
}

func hStack(_ views: [NSView], spacing: CGFloat = SettingsMetrics.spacing) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .firstBaseline
    stack.spacing = spacing
    return stack
}

/// An NSGridView that reports its first row's baseline, so it lines up with a form label.
final class BaselineGridView: NSGridView {
    override var firstBaselineOffsetFromTop: CGFloat {
        layoutSubtreeIfNeeded()
        guard numberOfRows > 0, numberOfColumns > 0, let first = cell(atColumnIndex: 0, rowIndex: 0).contentView else {
            return super.firstBaselineOffsetFromTop
        }
        let rect = convert(first.bounds, from: first)
        let top = isFlipped ? rect.minY : bounds.maxY - rect.maxY
        return top + first.firstBaselineOffsetFromTop
    }
}

func clamped(_ value: Int, _ range: ClosedRange<Int>) -> Int {
    min(range.upperBound, max(range.lowerBound, value))
}

/// A number field with an attached stepper. Commits on Return, focus loss, or a stepper click.
final class NumberStepperField: NSStackView, NSTextFieldDelegate {
    var onChange: ((Double) -> Void)?
    let field = NSTextField()
    let stepper = NSStepper()
    private let range: ClosedRange<Double>

    init(value: Double, range: ClosedRange<Double>, width: CGFloat = 48) {
        self.range = range
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 2
        field.alignment = .right
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.target = self
        stepper.action = #selector(stepped)
        addArrangedSubview(field)
        addArrangedSubview(stepper)
        setValue(value)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var firstBaselineOffsetFromTop: CGFloat {
        layoutSubtreeIfNeeded()
        let rect = convert(field.bounds, from: field)
        let top = isFlipped ? rect.minY : bounds.maxY - rect.maxY
        return top + field.firstBaselineOffsetFromTop
    }

    var isEnabled: Bool {
        get { field.isEnabled }
        set { field.isEnabled = newValue; stepper.isEnabled = newValue }
    }

    var doubleValue: Double { stepper.doubleValue }

    func setValue(_ value: Double) {
        let value = min(range.upperBound, max(range.lowerBound, value))
        stepper.doubleValue = value
        field.stringValue = value.rounded() == value ? String(Int(value)) : String(value)
    }

    @objc private func stepped() {
        setValue(stepper.doubleValue)
        onChange?(stepper.doubleValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let parsed = Double(field.stringValue.trimmingCharacters(in: .whitespaces)) ?? stepper.doubleValue
        setValue(parsed)
        onChange?(stepper.doubleValue)
    }
}
