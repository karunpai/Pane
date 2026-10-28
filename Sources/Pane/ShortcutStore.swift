import AppKit
import PaneCore

final class ShortcutStore {
    static let shared = ShortcutStore()
    private let defaults: UserDefaults
    private let storageKey = "windowShortcuts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcuts: [WindowShortcut] {
        get {
            guard let data = defaults.data(forKey: storageKey) else { return [] }
            return (try? JSONDecoder().decode([WindowShortcut].self, from: data)) ?? []
        }
    }

    func replaceShortcuts(_ candidates: [WindowShortcut], panel: PanelShortcut) throws {
        try ShortcutConflictValidator.validate(candidates, panel: panel)
        try persist(candidates)
    }

    /// The current shortcuts encoded as a `.paneshortcuts` file.
    func exportFileData(exportedAt: Date = Date()) throws -> Data {
        try ShortcutFile.encode(shortcuts, exportedAt: exportedAt)
    }

    /// Plans an import without touching persisted data. Throws if `data` isn't a valid shortcuts file.
    func previewImport(_ data: Data, mode: ShortcutImportMode, panel: PanelShortcut) throws -> ShortcutImportResult {
        let imported = try ShortcutFile.decode(data)
        return ShortcutImportPlanner.plan(existing: shortcuts, imported: imported, mode: mode, panel: panel)
    }

    /// Decodes, plans and persists an import. On any failure the stored shortcuts are unchanged.
    @discardableResult
    func importFile(_ data: Data, mode: ShortcutImportMode, panel: PanelShortcut) throws -> ShortcutImportResult {
        let result = try previewImport(data, mode: mode, panel: panel)
        try replaceShortcuts(result.shortcuts, panel: panel)
        return result
    }

    private func persist(_ shortcuts: [WindowShortcut]) throws {
        let data = try JSONEncoder().encode(shortcuts)
        defaults.set(data, forKey: storageKey)
    }
}
