import AppKit
import UniformTypeIdentifiers

/// AppKit flow shared by Settings → Import… and double-clicking a `.paneshortcuts` file in Finder:
/// read the file, ask Merge / Replace / Cancel, apply, then summarize what happened.
@MainActor
enum ShortcutFileImporter {
    static var contentType: UTType {
        UTType(ShortcutFile.typeIdentifier)
            ?? UTType(exportedAs: ShortcutFile.typeIdentifier, conformingTo: .json)
    }

    /// Types accepted by the open panel: the new format plus legacy plain-JSON exports.
    static var openableTypes: [UTType] { [contentType, .json] }

    /// Runs the full import flow. `window` hosts sheets when given; otherwise alerts are app-modal.
    /// `completion` receives true when the stored shortcuts changed.
    static func importFile(at url: URL, store: ShortcutStore = .shared, window: NSWindow?,
                           completion: ((Bool) -> Void)? = nil) {
        let data: Data
        let count: Int
        do {
            data = try Data(contentsOf: url)
            count = try ShortcutFile.decode(data).count
        } catch {
            show(errorAlert("Couldn’t import “\(url.lastPathComponent)”", error), in: window) { _ in completion?(false) }
            return
        }

        let existing = store.shortcuts.count
        let alert = NSAlert()
        alert.messageText = "Import \(count) shortcut\(count == 1 ? "" : "s") from “\(url.deletingPathExtension().lastPathComponent)”?"
        alert.informativeText = existing == 0
            ? "You don’t have any shortcuts yet."
            : "Merge adds them to your \(existing) existing shortcut\(existing == 1 ? "" : "s"), skipping exact duplicates. Shortcuts whose keys are already in use are imported disabled.\n\nReplace removes your current shortcuts first."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        show(alert, in: window) { response in
            let mode: ShortcutImportMode
            switch response {
            case .alertFirstButtonReturn: mode = .merge
            case .alertSecondButtonReturn: mode = .replace
            default: completion?(false); return
            }
            do {
                let result = try store.importFile(data, mode: mode, panel: AppPreferences.shared.panelShortcut)
                NotificationCenter.default.post(name: AppPreferences.shortcutsDidChangeNotification, object: store)
                show(summaryAlert(result, mode: mode), in: window) { _ in completion?(true) }
            } catch {
                show(errorAlert("Import failed — your shortcuts were not changed", error), in: window) { _ in completion?(false) }
            }
        }
    }

    /// Asks where to save, then writes the current shortcuts as a `.paneshortcuts` file.
    static func exportShortcuts(store: ShortcutStore = .shared, window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ShortcutFile.defaultExportName
        panel.allowedContentTypes = [contentType]
        panel.message = "Send this file to someone so they can import your shortcuts into Pane."
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try store.exportFileData().write(to: url, options: .atomic)
            } catch {
                show(errorAlert("Couldn’t export shortcuts", error), in: window) { _ in }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) }
        else { handler(panel.runModal()) }
    }

    private static func summaryAlert(_ result: ShortcutImportResult, mode: ShortcutImportMode) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = mode == .replace
            ? "Replaced your shortcuts with \(result.addedCount) imported shortcut\(result.addedCount == 1 ? "" : "s")"
            : "Imported \(result.addedCount) shortcut\(result.addedCount == 1 ? "" : "s")"
        var lines: [String] = []
        if result.skippedDuplicateCount > 0 {
            lines.append("Skipped \(result.skippedDuplicateCount) you already had.")
        }
        if !result.disabledForConflict.isEmpty {
            lines.append("These were imported disabled because their keys are already used by another shortcut or the panel shortcut. Give them new keys in Settings → Shortcuts to use them:\n"
                + result.disabledForConflict.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !result.renamed.isEmpty {
            lines.append("Renamed to avoid duplicate names:\n"
                + result.renamed.map { "• \($0.from) → \($0.to)" }.joined(separator: "\n"))
        }
        alert.informativeText = lines.isEmpty ? "All shortcuts are ready to use." : lines.joined(separator: "\n\n")
        if !result.disabledForConflict.isEmpty { alert.alertStyle = .warning }
        return alert
    }

    private static func errorAlert(_ title: String, _ error: Error) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        if error is DecodingError || (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == 3840 {
            alert.informativeText = ShortcutFile.DecodeError.notAShortcutsFile.localizedDescription
        } else {
            alert.informativeText = error.localizedDescription
        }
        return alert
    }

    private static func show(_ alert: NSAlert, in window: NSWindow?,
                             completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            completion(alert.runModal())
        }
    }
}
