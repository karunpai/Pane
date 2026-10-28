import AppKit
import Carbon
import PaneCore

protocol GridViewDelegate: AnyObject {
    func gridView(_ view: GridView, previewed selection: GridSelection)
    func gridView(_ view: GridView, committed selection: GridSelection, invertDismiss: Bool)
    func gridViewClearedPreview(_ view: GridView)
    func gridViewRequestedDismiss(_ view: GridView)
}

/// The selection grid: outlined rounded cells; hover highlights one
/// cell, press-drag-release selects a rectangle and commits it.
final class GridView: NSView {
    weak var delegate: GridViewDelegate?
    var rows = 6 { didSet { if rows != oldValue { resetInteraction() } } }
    var columns = 6 { didSet { if columns != oldValue { resetInteraction() } } }

    private(set) var isSubdivided = false
    private var optionWasDown = false
    private var anchor: (row: Int, column: Int)?
    private var current: GridSelection?

    var effectiveRows: Int { rows * (isSubdivided ? 2 : 1) }
    var effectiveColumns: Int { columns * (isSubdivided ? 2 : 1) }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // The panel may not be key yet when the user presses; never swallow that click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Called each time the overlay is shown.
    func prepareForDisplay() {
        isSubdivided = false
        optionWasDown = NSEvent.modifierFlags.contains(.option)
        anchor = nil
        current = nil
        needsDisplay = true
    }

    /// Forces the 2x (Option) grid without user input (used for snapshots).
    func setSubdividedForSnapshot(_ value: Bool) {
        isSubdivided = value
        needsDisplay = true
    }

    /// Shows a selection without user input (used for snapshots).
    func showSelection(_ selection: GridSelection?) {
        current = selection
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rowCount = effectiveRows, columnCount = effectiveColumns
        let cellWidth = bounds.width / CGFloat(columnCount)
        let cellHeight = bounds.height / CGFloat(rowCount)
        let gap = max(2, min(6, min(cellWidth, cellHeight) * 0.14))
        let radius = min(3, min(cellWidth, cellHeight) * 0.12)
        let accent = NSColor.controlAccentColor
        let idleStroke = NSColor(white: 1, alpha: 0.42)
        let idleFill = NSColor(white: 1, alpha: 0.03)

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let raw = cellRect(row: row, column: column).insetBy(dx: gap / 2, dy: gap / 2)
                guard raw.intersects(dirtyRect) else { continue }
                // Align to device pixels, then inset half a point so 1pt strokes are crisp.
                let rect = backingAlignedRect(raw, options: .alignAllEdgesNearest).insetBy(dx: 0.5, dy: 0.5)
                let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                path.lineWidth = 1
                if isSelected(row: row, column: column) {
                    accent.withAlphaComponent(0.88).setFill()
                    path.fill()
                    accent.highlight(withLevel: 0.25)?.setStroke()
                    path.stroke()
                } else {
                    idleFill.setFill()
                    path.fill()
                    idleStroke.setStroke()
                    path.stroke()
                }
            }
        }
    }

    private func isSelected(row: Int, column: Int) -> Bool {
        guard let current else { return false }
        return row >= current.startRow && row <= current.endRow
            && column >= current.startColumn && column <= current.endColumn
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let cell = cell(at: convert(event.locationInWindow, from: nil))
        anchor = cell
        updateSelection(to: cell)
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(to: cell(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        guard anchor != nil else { return }
        updateSelection(to: cell(at: convert(event.locationInWindow, from: nil)))
        anchor = nil
        if let current {
            delegate?.gridView(self, committed: current, invertDismiss: event.modifierFlags.contains(.shift))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard anchor == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let hovered = cell(at: point)
        let selection = GridSelection(startRow: hovered.row, startColumn: hovered.column,
                                      endRow: hovered.row, endColumn: hovered.column)
        guard selection != current else { return }
        current = selection
        needsDisplay = true
        delegate?.gridView(self, previewed: selection)
    }

    override func mouseExited(with event: NSEvent) {
        if anchor == nil { clearSelection() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    // MARK: Keyboard

    override func flagsChanged(with event: NSEvent) {
        let down = event.modifierFlags.contains(.option)
        if down && !optionWasDown {
            isSubdivided.toggle()
            resetInteraction()
        }
        optionWasDown = down
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if current != nil { clearSelection() } else { delegate?.gridViewRequestedDismiss(self) }
            return
        }
        if handleGridSizeKey(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleGridSizeKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Cmd+= / Cmd+- change rows; with Shift they change columns.
    private func handleGridSizeKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else { return false }
        let shift = event.modifierFlags.contains(.shift)
        let prefs = AppPreferences.shared
        switch Int(event.keyCode) {
        case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
            if shift { prefs.columns = columns + 1 } else { prefs.rows = rows + 1 }
        case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
            if shift { prefs.columns = columns - 1 } else { prefs.rows = rows - 1 }
        default:
            return false
        }
        // The controller observes preference changes and resizes the panel.
        rows = prefs.rows
        columns = prefs.columns
        return true
    }

    // MARK: Selection helpers

    private func resetInteraction() {
        current = nil
        anchor = nil
        needsDisplay = true
        delegate?.gridViewClearedPreview(self)
    }

    private func clearSelection() { resetInteraction() }

    private func updateSelection(to cell: (row: Int, column: Int)) {
        guard let anchor else { return }
        let selection = GridSelection(startRow: anchor.row, startColumn: anchor.column,
                                      endRow: cell.row, endColumn: cell.column)
        let changed = selection != current
        current = selection
        if changed {
            needsDisplay = true
            delegate?.gridView(self, previewed: selection)
        }
    }

    private func cell(at point: CGPoint) -> (row: Int, column: Int) {
        let column = Int(point.x / max(1, bounds.width) * CGFloat(effectiveColumns))
        let row = Int(point.y / max(1, bounds.height) * CGFloat(effectiveRows))
        return (min(effectiveRows - 1, max(0, row)), min(effectiveColumns - 1, max(0, column)))
    }

    private func cellRect(row: Int, column: Int) -> CGRect {
        let width = bounds.width / CGFloat(effectiveColumns)
        let height = bounds.height / CGFloat(effectiveRows)
        return CGRect(x: CGFloat(column) * width, y: CGFloat(row) * height, width: width, height: height)
    }
}
