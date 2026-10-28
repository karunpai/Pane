import AppKit

/// On-screen resize preview: a translucent accent-tinted rounded rectangle
/// showing where the target window will land. Ignores the mouse and sits above
/// normal windows but below the overlay panel.
final class OverlayPreviewWindow: NSWindow {
    private let box = NSView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .floating
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let root = NSView()
        root.wantsLayer = true
        box.wantsLayer = true
        box.autoresizingMask = [.width, .height]
        box.layer?.cornerRadius = 10
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 2
        root.addSubview(box)
        contentView = root
        updateColors()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(frame: CGRect) {
        updateColors()
        box.frame = NSRect(origin: .zero, size: frame.size)
        let wasVisible = isVisible
        setFrame(frame, display: true)
        guard !wasVisible else { return }
        let animate = AppPreferences.shared.animationsEnabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = animate ? 0 : 1
        orderFront(nil)
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
    }

    private func updateColors() {
        let accent = NSColor.controlAccentColor
        box.layer?.backgroundColor = accent.withAlphaComponent(0.2).cgColor
        box.layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
    }
}
