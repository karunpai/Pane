import CoreGraphics
import Foundation

/// Where the Mac's built-in display sits relative to the external monitor.
public enum MacPosition: String, Codable, CaseIterable, Sendable {
    case left, right, above, below
}

/// How the Mac lines up along the shared edge.
/// For `.left`/`.right`: start = top edges, end = bottom edges.
/// For `.above`/`.below`: start = left edges, end = right edges.
public enum LayoutAlignment: String, Codable, CaseIterable, Sendable {
    case start, center, end
}

/// Which display carries the menu bar (the main display, placed at the origin).
public enum MenuBarLocation: String, Codable, CaseIterable, Sendable {
    case mac, monitor
}

/// A modifier key that triggers a layout when tapped twice on its own.
public enum DoubleTapKey: String, Codable, CaseIterable, Sendable {
    case option, command, control, shift
}

/// A saved display arrangement, chosen by double-tapping `trigger`.
public struct DisplayLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: DoubleTapKey
    public var position: MacPosition
    public var alignment: LayoutAlignment
    public var menuBar: MenuBarLocation

    public init(id: UUID = UUID(), name: String, trigger: DoubleTapKey,
                position: MacPosition, alignment: LayoutAlignment, menuBar: MenuBarLocation) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.position = position
        self.alignment = alignment
        self.menuBar = menuBar
    }

    /// The two layouts Pane starts with.
    public static let defaults: [DisplayLayout] = [
        DisplayLayout(id: UUID(uuidString: "6B1F0E52-6C7A-4C1E-9C1B-5A0E7C2D0001")!,
                      name: "Mac on left", trigger: .option, position: .left, alignment: .end, menuBar: .mac),
        DisplayLayout(id: UUID(uuidString: "6B1F0E52-6C7A-4C1E-9C1B-5A0E7C2D0002")!,
                      name: "Mac below", trigger: .command, position: .below, alignment: .center, menuBar: .mac)
    ]

    /// Global display origins (Core Graphics coordinates: y grows downward, the
    /// display at (0, 0) is the main display) for a Mac and monitor of these sizes.
    public func origins(mac: CGSize, monitor: CGSize) -> (mac: CGPoint, monitor: CGPoint) {
        func align(_ macLength: CGFloat, _ monitorLength: CGFloat) -> CGFloat {
            switch alignment {
            case .start: return 0
            case .center: return ((macLength - monitorLength) / 2).rounded()
            case .end: return macLength - monitorLength
            }
        }
        // Monitor origin with the Mac at (0, 0).
        let relative: CGPoint
        switch position {
        case .left: relative = CGPoint(x: mac.width, y: align(mac.height, monitor.height))
        case .right: relative = CGPoint(x: -monitor.width, y: align(mac.height, monitor.height))
        case .below: relative = CGPoint(x: align(mac.width, monitor.width), y: -monitor.height)
        case .above: relative = CGPoint(x: align(mac.width, monitor.width), y: mac.height)
        }
        switch menuBar {
        case .mac: return (.zero, relative)
        case .monitor: return (CGPoint(x: -relative.x, y: -relative.y), .zero)
        }
    }

    /// Triggers used by more than one layout.
    public static func duplicateTriggers(in layouts: [DisplayLayout]) -> Set<DoubleTapKey> {
        var seen = Set<DoubleTapKey>()
        var duplicates = Set<DoubleTapKey>()
        for layout in layouts where !seen.insert(layout.trigger).inserted {
            duplicates.insert(layout.trigger)
        }
        return duplicates
    }
}

/// Recognises a modifier key pressed and released on its own twice in quick
/// succession. Feed it every modifier change and every ordinary key press.
public struct DoubleTapDetector: Sendable {
    /// Longest a single tap may be held down.
    public var maxHold: TimeInterval = 0.35
    /// Longest gap from the first tap's release to the second tap's press.
    public var maxGap: TimeInterval = 0.45

    private var downKey: DoubleTapKey?
    private var downAt: TimeInterval = 0
    private var tapIsClean = false
    private var lastTap: (key: DoubleTapKey, releasedAt: TimeInterval)?

    public init() {}

    /// Call with the set of modifiers now held. Returns a key when its double-tap completes.
    public mutating func modifiersChanged(_ held: Set<DoubleTapKey>, at time: TimeInterval) -> DoubleTapKey? {
        if held.count == 1, let key = held.first, downKey == nil {
            // A single modifier went down on its own.
            if let last = lastTap, last.key != key || time - last.releasedAt > maxGap { lastTap = nil }
            downKey = key
            downAt = time
            tapIsClean = true
            return nil
        }
        if held.isEmpty, let key = downKey {
            let clean = tapIsClean && time - downAt <= maxHold
            downKey = nil
            guard clean else { lastTap = nil; return nil }
            if let last = lastTap, last.key == key {
                lastTap = nil
                return key
            }
            lastTap = (key, time)
            return nil
        }
        // A second modifier joined, or a different combination: not a tap.
        tapIsClean = false
        lastTap = nil
        return nil
    }

    /// Call for any ordinary (non-modifier) key press.
    public mutating func keyPressed(at time: TimeInterval) {
        tapIsClean = false
        lastTap = nil
    }
}
