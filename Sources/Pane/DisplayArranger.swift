import CoreGraphics
import Foundation
import PaneCore

/// Moves the built-in display and one external monitor into a `DisplayLayout`,
/// the same change as dragging them in System Settings → Displays → Arrange.
enum DisplayArranger {
    enum Outcome: Equatable {
        case applied
        case noMonitor
        case builtInDisplayOff
        case failed(Int32)

        /// Text for an alert or log line when the layout couldn't be applied.
        var problem: String? {
            switch self {
            case .applied: return nil
            case .noMonitor: return "No external monitor is connected."
            case .builtInDisplayOff: return "The Mac's own display is off (lid closed), so there's nothing to arrange."
            case .failed(let code): return "macOS refused the new arrangement (error \(code))."
            }
        }
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static var builtInDisplay: CGDirectDisplayID? {
        activeDisplays().first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// External monitors that are on and not mirroring another display.
    static func externalDisplays() -> [CGDirectDisplayID] {
        activeDisplays().filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }

    /// Applies `layout` to `monitor` (default: the first external monitor).
    @discardableResult
    static func apply(_ layout: DisplayLayout, to monitor: CGDirectDisplayID? = nil) -> Outcome {
        guard let mac = builtInDisplay else { return .builtInDisplayOff }
        guard let external = monitor ?? externalDisplays().first,
              externalDisplays().contains(external) else { return .noMonitor }

        let origins = layout.origins(mac: CGDisplayBounds(mac).size, monitor: CGDisplayBounds(external).size)
        var config: CGDisplayConfigRef?
        var status = CGBeginDisplayConfiguration(&config)
        guard status == .success, let config else { return .failed(status.rawValue) }

        // Any other external monitors keep their place relative to the main display.
        status = CGConfigureDisplayOrigin(config, mac, Int32(origins.mac.x), Int32(origins.mac.y))
        if status == .success {
            status = CGConfigureDisplayOrigin(config, external, Int32(origins.monitor.x), Int32(origins.monitor.y))
        }
        guard status == .success else {
            CGCancelDisplayConfiguration(config)
            return .failed(status.rawValue)
        }
        status = CGCompleteDisplayConfiguration(config, .permanently)
        if status != .success { NSLog("Pane: display arrangement failed: %d", status.rawValue) }
        return status == .success ? .applied : .failed(status.rawValue)
    }
}
