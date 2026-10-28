import AppKit
import PaneCore

/// Owns the grid overlay panel and the on-screen resize preview.
///
/// The panel is a borderless `.nonactivatingPanel` (see `OverlayPanel`): it
/// becomes key without activating Pane, so the target app stays frontmost and
/// the first click on the grid is delivered straight to `GridView` (which also
/// accepts first mouse). That is what makes press-drag-release selection work.
final class OverlayController: NSWindowController, NSWindowDelegate, GridViewDelegate, OverlayContentViewDelegate {
    private let panel: OverlayPanel
    private let overlayView: OverlayContentView
    private var gridView: GridView { overlayView.gridView }
    private let windowManager: WindowManager
    private var target: WindowManager.Target?
    private var targetScreen: NSScreen?
    private lazy var previewWindow = OverlayPreviewWindow()
    private var isDismissing = false
    /// When a click elsewhere (e.g. on the menu bar icon) dismissed the panel by
    /// taking key status, the same click must not immediately re-open it.
    private var lastResignDismissal = Date.distantPast

    private var animationsAllowed: Bool {
        AppPreferences.shared.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        let prefs = AppPreferences.shared
        let size = OverlayMetrics.panelSize(rows: prefs.rows, columns: prefs.columns)
        panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: size))
        overlayView = OverlayContentView(frame: NSRect(origin: .zero, size: size))
        super.init(window: panel)
        overlayView.autoresizingMask = [.width, .height]
        panel.contentView = overlayView
        panel.delegate = self
        gridView.delegate = self
        overlayView.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: AppPreferences.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private var isShowing: Bool { panel.isVisible && !isDismissing }

    func toggle() {
        if isShowing { dismiss(); return }
        if Date().timeIntervalSince(lastResignDismissal) < 0.35 { return }
        guard windowManager.requestAccessibilityPermission(prompt: true) else { return }
        // Capture the target before anything of ours appears; the panel never
        // activates Pane, so this app stays frontmost while the grid is up.
        target = windowManager.captureFrontmostWindow()
        targetScreen = screenContainingMouse() ?? NSScreen.main
        show()
    }

    private func show() {
        let prefs = AppPreferences.shared
        if prefs.useDefaultGrid {
            prefs.rows = prefs.defaultRows
            prefs.columns = prefs.defaultColumns
        }
        overlayView.configure(appName: target?.app.localizedName, icon: target?.app.icon)
        overlayView.resetToFront()
        overlayView.refreshSettings()
        gridView.rows = prefs.rows
        gridView.columns = prefs.columns
        gridView.prepareForDisplay()

        let size = OverlayMetrics.panelSize(rows: prefs.rows, columns: prefs.columns)
        let visible = (targetScreen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let frame = NSRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: false)

        isDismissing = false
        let animate = animationsAllowed
        panel.alphaValue = animate ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gridView)
        panel.invalidateShadow()
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func applyPreset(_ selection: GridSelection) {
        guard windowManager.requestAccessibilityPermission(prompt: false),
              let target = windowManager.captureFrontmostWindow(),
              let screen = windowManager.screen(containing: target) ?? NSScreen.main else { return }
        let frame = frame(using: geometry, selection: selection, screen: screen)
        _ = windowManager.move(target, to: frame)
    }

    func applyShortcut(_ shortcut: WindowShortcut, cycleFrom previousScreen: NSScreen? = nil) -> NSScreen? {
        guard windowManager.requestAccessibilityPermission(prompt: false),
              let target = windowManager.captureFrontmostWindow() else { return nil }
        let screens = NSScreen.screens.sorted {
            if $0.frame.minX == $1.frame.minX { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX < $1.frame.minX
        }
        var screen = windowManager.screen(containing: target) ?? NSScreen.main
        if let previousScreen, AppPreferences.shared.cycleDisplays,
           let index = screens.firstIndex(of: previousScreen), !screens.isEmpty {
            screen = screens[(index + 1) % screens.count]
        }
        guard let screen else { return nil }
        let multiplier = shortcut.isSubdivided ? 2 : 1
        let shortcutGeometry = GridGeometry(rows: shortcut.rows * multiplier,
                                            columns: shortcut.columns * multiplier,
                                            outerMargin: 0, gap: 0)
        let targetFrame = frame(using: shortcutGeometry, selection: shortcut.selection, screen: screen)
        _ = windowManager.move(target, to: targetFrame)
        return screen
    }

    // MARK: GridViewDelegate

    func gridView(_ view: GridView, previewed selection: GridSelection) {
        guard AppPreferences.shared.showPreview, target != nil, let screen = targetScreen else { return }
        previewWindow.show(frame: frame(using: geometry(for: view), selection: selection, screen: screen))
    }

    func gridView(_ view: GridView, committed selection: GridSelection, invertDismiss: Bool) {
        previewWindow.hide()
        if let target, let screen = targetScreen {
            _ = windowManager.move(target, to: frame(using: geometry(for: view), selection: selection, screen: screen))
        }
        let shouldDismiss = !AppPreferences.shared.keepOpen
        if shouldDismiss != invertDismiss { dismiss() }
    }

    func gridViewClearedPreview(_ view: GridView) { previewWindow.hide() }
    func gridViewRequestedDismiss(_ view: GridView) { dismiss() }

    // MARK: OverlayContentViewDelegate

    func overlayContentViewRequestedClose(_ view: OverlayContentView) { dismiss() }

    func overlayContentViewRequestedSettings(_ view: OverlayContentView) {
        dismiss(animated: false)
        NotificationCenter.default.post(name: AppPreferences.openSettingsRequestedNotification, object: self)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard isShowing else { return }
        lastResignDismissal = Date()
        dismiss()
    }

    // MARK: Helpers

    @objc private func preferencesChanged() {
        guard isShowing else { return }
        let prefs = AppPreferences.shared
        guard gridView.rows != prefs.rows || gridView.columns != prefs.columns else { return }
        gridView.rows = prefs.rows
        gridView.columns = prefs.columns
        resizePanelKeepingCenter()
    }

    private func resizePanelKeepingCenter() {
        let size = OverlayMetrics.panelSize(rows: gridView.rows, columns: gridView.columns)
        let old = panel.frame
        var frame = NSRect(x: (old.midX - size.width / 2).rounded(), y: (old.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        if let visible = panel.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private var geometry: GridGeometry {
        let prefs = AppPreferences.shared
        return GridGeometry(rows: prefs.rows, columns: prefs.columns, outerMargin: 0, gap: 0)
    }

    private func geometry(for view: GridView) -> GridGeometry {
        GridGeometry(rows: view.effectiveRows, columns: view.effectiveColumns, outerMargin: 0, gap: 0)
    }

    private func frame(using geometry: GridGeometry, selection: GridSelection, screen: NSScreen) -> CGRect {
        let prefs = AppPreferences.shared
        guard prefs.marginsEnabled else { return geometry.frame(for: selection, in: screen.visibleFrame) }
        return geometry.frame(for: selection, in: screen.visibleFrame,
                              edgeInsets: EdgeInsets(left: prefs.marginLeft, right: prefs.marginRight,
                                                     top: prefs.marginTop, bottom: prefs.marginBottom),
                              horizontalGap: prefs.horizontalGap, verticalGap: prefs.verticalGap)
    }

    private func dismiss(animated: Bool = true) {
        previewWindow.hide()
        target = nil
        guard panel.isVisible, !isDismissing else { return }
        guard animated, animationsAllowed else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        isDismissing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.isDismissing else { return }
            self.isDismissing = false
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
