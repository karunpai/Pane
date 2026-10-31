import AppKit
import PaneCore

/// Draws a `DisplayLayout` the way System Settings → Displays → Arrange does: the Mac
/// (smaller, accent-tinted) and the monitor as rounded rectangles in their relative
/// positions, with a menu-bar strip across the top of the main display.
/// `.thumbnail` is the list-row icon; `.preview` is the larger, labelled editor view.
final class DisplayArrangementView: NSView {
    enum Style { case thumbnail, preview }

    /// Representative sizes (points): a 14" MacBook Pro and a 6K monitor.
    static let macSize = CGSize(width: 1512, height: 982)
    static let monitorSize = CGSize(width: 3360, height: 1890)

    static let thumbnailSize = NSSize(width: 52, height: 32)
    static let previewSize = NSSize(width: 220, height: 150)

    var layout: DisplayLayout {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(accessibilityText)
        }
    }
    private let style: Style

    init(layout: DisplayLayout, style: Style) {
        self.layout = layout
        self.style = style
        let size = style == .thumbnail ? Self.thumbnailSize : Self.previewSize
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(accessibilityText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private var accessibilityText: String {
        "Display arrangement: Mac \(layout.summary.lowercased()), menu bar on the \(layout.menuBar == .mac ? "Mac" : "monitor")"
    }

    /// Both displays scaled to fit `area` and centered in it (flipped coordinates, like CG).
    private func displayRects(in area: CGRect) -> (mac: CGRect, monitor: CGRect) {
        let origins = layout.origins(mac: Self.macSize, monitor: Self.monitorSize)
        let mac = CGRect(origin: origins.mac, size: Self.macSize)
        let monitor = CGRect(origin: origins.monitor, size: Self.monitorSize)
        let union = mac.union(monitor)
        let scale = min(area.width / union.width, area.height / union.height)
        let offset = CGPoint(x: area.minX + (area.width - union.width * scale) / 2,
                             y: area.minY + (area.height - union.height * scale) / 2)
        func map(_ rect: CGRect) -> CGRect {
            CGRect(x: offset.x + (rect.minX - union.minX) * scale, y: offset.y + (rect.minY - union.minY) * scale,
                   width: rect.width * scale, height: rect.height * scale)
        }
        return (map(mac), map(monitor))
    }

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .thumbnail: drawThumbnail()
        case .preview: drawPreview()
        }
    }

    private func drawThumbnail() {
        let rects = displayRects(in: bounds.insetBy(dx: 1, dy: 1))
        // A hairline gap between the two displays, so they read as two screens.
        let monitor = rects.monitor.insetBy(dx: 0.75, dy: 0.75)
        let mac = rects.mac.insetBy(dx: 0.75, dy: 0.75)

        let monitorPath = NSBezierPath(roundedRect: monitor, xRadius: 2.5, yRadius: 2.5)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        monitorPath.fill()
        NSColor.labelColor.withAlphaComponent(0.3).setStroke()
        monitorPath.lineWidth = 1
        monitorPath.stroke()

        let macPath = NSBezierPath(roundedRect: mac, xRadius: 2, yRadius: 2)
        NSColor.controlAccentColor.setFill()
        macPath.fill()

        let main = layout.menuBar == .mac ? mac : monitor
        let strip = NSRect(x: main.minX + 0.5, y: main.minY + 0.5, width: main.width - 1, height: 2.5)
        NSGraphicsContext.saveGraphicsState()
        (layout.menuBar == .mac ? macPath : monitorPath).addClip()
        (layout.menuBar == .mac ? NSColor.white.withAlphaComponent(0.75) : NSColor.labelColor.withAlphaComponent(0.45)).setFill()
        strip.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPreview() {
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        frame.fill()
        NSColor.separatorColor.setStroke()
        frame.stroke()

        let rects = displayRects(in: bounds.insetBy(dx: 18, dy: 18))
        let monitor = rects.monitor.insetBy(dx: 1.5, dy: 1.5)
        let mac = rects.mac.insetBy(dx: 1.5, dy: 1.5)
        let accent = NSColor.controlAccentColor

        drawDisplay(monitor, radius: 6, fill: NSColor.labelColor.withAlphaComponent(0.06),
                    stroke: NSColor.labelColor.withAlphaComponent(0.28), strip: NSColor.labelColor.withAlphaComponent(0.4),
                    isMain: layout.menuBar == .monitor, title: "Monitor", titleColor: .secondaryLabelColor)
        drawDisplay(mac, radius: 4, fill: accent.withAlphaComponent(0.22),
                    stroke: accent.withAlphaComponent(0.9), strip: accent.withAlphaComponent(0.85),
                    isMain: layout.menuBar == .mac, title: "Mac", titleColor: .labelColor)
    }

    private func drawDisplay(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor, strip: NSColor,
                             isMain: Bool, title: String, titleColor: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        if isMain {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            strip.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 5).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: titleColor
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        guard size.width < rect.width - 4 else { return }
        let top = isMain ? 5 : 0
        text.draw(at: NSPoint(x: rect.midX - size.width / 2,
                              y: rect.minY + CGFloat(top) + (rect.height - CGFloat(top) - size.height) / 2))
    }
}
