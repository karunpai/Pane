import AppKit
import CoreGraphics
import PaneCore

/// When an external monitor is connected, listens for one minute for a
/// double-tapped modifier key and applies the matching `DisplayLayout`.
/// Outside that minute, double-taps do nothing.
@MainActor
final class DisplayShortcutController {
    static let listenDuration: TimeInterval = 60

    private let store: DisplayLayoutStore
    private var detector = DoubleTapDetector()
    private var monitors: [Any] = []
    private var stopTimer: Timer?
    private var targetDisplay: CGDirectDisplayID?
    private var isRegistered = false

    init(store: DisplayLayoutStore = .shared) {
        self.store = store
    }

    var isListening: Bool { targetDisplay != nil }

    func start() {
        guard !isRegistered else { return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ display, flags, userInfo in
            // Only a newly added external display counts; our own rearranging
            // reports move flags, not add flags.
            guard flags.contains(.addFlag), !flags.contains(.beginConfigurationFlag),
                  CGDisplayIsBuiltin(display) == 0, let userInfo else { return }
            let controller = Unmanaged<DisplayShortcutController>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { controller.monitorConnected(display) }
            }
        }, pointer)
        isRegistered = true
    }

    /// Begins the listening minute for `display`. Restarts it if another monitor arrives.
    func monitorConnected(_ display: CGDirectDisplayID) {
        guard store.isEnabled, !store.layouts.isEmpty else { return }
        guard DisplayArranger.builtInDisplay != nil else { return } // lid closed: nothing to arrange
        NSLog("Pane: monitor %u connected; listening %.0fs for a layout double-tap", display, Self.listenDuration)
        stopListening()
        targetDisplay = display
        detector = DoubleTapDetector()
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
        stopTimer = Timer.scheduledTimer(withTimeInterval: Self.listenDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopListening() }
        }
    }

    func stopListening() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        stopTimer?.invalidate()
        stopTimer = nil
        targetDisplay = nil
    }

    private func handle(_ event: NSEvent) {
        let time = event.timestamp
        switch event.type {
        case .keyDown:
            detector.keyPressed(at: time)
        case .flagsChanged:
            guard let key = detector.modifiersChanged(Self.keys(in: event.modifierFlags), at: time),
                  let layout = store.layout(for: key) else { return }
            apply(layout)
        default:
            break
        }
    }

    private func apply(_ layout: DisplayLayout) {
        let display = targetDisplay
        stopListening()
        let outcome = DisplayArranger.apply(layout, to: display)
        if let problem = outcome.problem {
            DisplayToast.show(problem, symbol: "exclamationmark.triangle.fill")
        } else {
            DisplayToast.show(layout.name, symbol: "display.2")
        }
    }

    /// The trigger keys held in `flags`.
    static func keys(in flags: NSEvent.ModifierFlags) -> Set<DoubleTapKey> {
        var keys = Set<DoubleTapKey>()
        if flags.contains(.option) { keys.insert(.option) }
        if flags.contains(.command) { keys.insert(.command) }
        if flags.contains(.control) { keys.insert(.control) }
        if flags.contains(.shift) { keys.insert(.shift) }
        return keys
    }
}

/// A brief rounded HUD message in the middle-top of the main display.
@MainActor
enum DisplayToast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String) {
        // Let macOS finish moving displays before placing the message.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { present(text, symbol: symbol) }
    }

    private static func present(_ text: String, symbol: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .white
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 20)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        let size = stack.fittingSize

        let toast = panel ?? {
            let new = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            new.isOpaque = false
            new.backgroundColor = .clear
            new.hasShadow = true
            new.level = .statusBar
            new.ignoresMouseEvents = true
            new.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            new.appearance = NSAppearance(named: .darkAqua)
            panel = new
            return new
        }()
        toast.contentView = effect
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            toast.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 80,
                                  width: size.width, height: size.height), display: true)
        }
        toast.alphaValue = 1
        toast.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                toast.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { toast.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}
