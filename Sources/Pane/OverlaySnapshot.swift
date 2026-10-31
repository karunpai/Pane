import AppKit
import PaneCore

/// Debug helper behind `--snapshot-overlay <dir>`: renders the overlay's front
/// and back sides to PNGs without hotkeys, a status item, or any visible window.
enum OverlaySnapshot {
    static func run(outputDirectory: String) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Could not create \(directory.path): \(error)")
            return 1
        }

        let rows = 10, columns = 10
        let size = OverlayMetrics.panelSize(rows: rows, columns: columns)
        let margin: CGFloat = 36
        let panel = OverlayPanel(contentRect: NSRect(x: -10_000, y: -10_000,
                                                     width: size.width + margin * 2, height: size.height + margin * 2))
        let backdrop = SnapshotBackdropView(frame: NSRect(origin: .zero, size: panel.frame.size))
        let overlay = OverlayContentView(frame: NSRect(x: margin, y: margin, width: size.width, height: size.height))
        overlay.configure(appName: "Terminal",
                          icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"))
        overlay.useFlatBackgroundForSnapshot()
        overlay.gridView.rows = rows
        overlay.gridView.columns = columns
        overlay.gridView.showSelection(GridSelection(startRow: 0, startColumn: 0, endRow: 9, endColumn: 4))
        backdrop.addSubview(overlay)
        panel.contentView = backdrop
        overlay.layoutSubtreeIfNeeded()

        var status: Int32 = 0
        if !write(backdrop, to: directory.appendingPathComponent("overlay-front.png")) { status = 1 }
        overlay.setShowingBack(true, animated: false)
        overlay.layoutSubtreeIfNeeded()
        if !write(backdrop, to: directory.appendingPathComponent("overlay-back.png")) { status = 1 }

        // Option held: the finer 2x grid.
        overlay.setShowingBack(false, animated: false)
        overlay.gridView.setSubdividedForSnapshot(true)
        overlay.gridView.showSelection(GridSelection(startRow: 2, startColumn: 3, endRow: 13, endColumn: 16))
        overlay.layoutSubtreeIfNeeded()
        if !write(backdrop, to: directory.appendingPathComponent("overlay-fine-grid.png")) { status = 1 }

        // Each Settings tab in dark and light, rendered from the window's frame view so the
        // background and toolbar are included.
        let settings = SettingsWindowController()
        if let window = settings.window, let tabs = window.contentViewController as? NSTabViewController {
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            for (appearance, suffix) in [(NSAppearance.Name.darkAqua, ""), (.aqua, "-light")] {
                window.appearance = NSAppearance(named: appearance)
                for (index, name) in ["general", "appearance", "shortcuts", "displays"].enumerated() {
                    tabs.selectedTabViewItemIndex = index
                    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                    window.layoutIfNeeded()
                    window.display()
                    if let frameView = window.contentView?.superview,
                       !write(frameView, to: directory.appendingPathComponent("settings-\(name)\(suffix).png"), appearance: nil) {
                        status = 1
                    }
                }
            }
            window.orderOut(nil)
        }

        // The New/Edit Shortcut sheet (drawn as a titled window; as a sheet it has no title bar).
        if let editor = SettingsWindowController.makeEditorWindowForSnapshot() {
            editor.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            editor.orderFrontRegardless()
            editor.makeFirstResponder(nil)
            for (appearance, suffix) in [(NSAppearance.Name.darkAqua, ""), (.aqua, "-light")] {
                editor.appearance = NSAppearance(named: appearance)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                editor.layoutIfNeeded()
                editor.display()
                if let content = editor.contentView?.superview,
                   !write(content, to: directory.appendingPathComponent("settings-editor\(suffix).png"), appearance: nil) {
                    status = 1
                }
            }
            editor.orderOut(nil)
        }
        // The New/Edit Layout sheet (Displays tab). Building it never touches the displays.
        if let editor = DisplayLayoutEditorWindowController.makeWindowForSnapshot() {
            editor.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            editor.orderFrontRegardless()
            editor.makeFirstResponder(nil)
            for (appearance, suffix) in [(NSAppearance.Name.darkAqua, ""), (.aqua, "-light")] {
                editor.appearance = NSAppearance(named: appearance)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                editor.layoutIfNeeded()
                editor.display()
                if let content = editor.contentView?.superview,
                   !write(content, to: directory.appendingPathComponent("settings-display-editor\(suffix).png"), appearance: nil) {
                    status = 1
                }
            }
            editor.orderOut(nil)
        }
        return status
    }

    private static func write(_ view: NSView, to url: URL,
                              appearance: NSAppearance? = NSAppearance(named: .darkAqua)) -> Bool {
        if let appearance { view.appearance = appearance }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            print("Wrote \(url.path)")
            return true
        } catch {
            print("Failed to write \(url.path): \(error)")
            return false
        }
    }
}

/// Stand-in for the desktop behind the panel (a behind-window blur has nothing
/// to sample in an offscreen render), so the snapshot reads like the real thing.
private final class SnapshotBackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.48, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.50, blue: 0.42, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: -60)
    }
}
