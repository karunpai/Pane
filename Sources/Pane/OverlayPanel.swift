import AppKit

/// Borderless, non-activating floating panel for the grid overlay.
///
/// `.nonactivatingPanel` lets the panel become key (receiving clicks, drags and
/// keys) without activating Pane, so the window the user wants to move keeps its
/// app frontmost. Being borderless there is no titlebar drag region, and the
/// panel can't be moved by dragging, so every mouseDown reaches the grid.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .modalPanel
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        worksWhenModal = true
        isMovable = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // The overlay is always a dark HUD, regardless of system appearance.
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Small borderless SF Symbol button used in the overlay header.
final class OverlayIconButton: NSButton {
    private var hovering = false { didSet { updateTint() } }

    convenience init(symbol: String, pointSize: CGFloat, label: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(configuration)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        toolTip = label
        setAccessibilityLabel(label)
        self.target = target
        self.action = action
        focusRingType = .none
        refusesFirstResponder = true
        updateTint()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func updateTint() {
        contentTintColor = NSColor(white: 1, alpha: hovering ? 0.95 : 0.62)
    }
}
