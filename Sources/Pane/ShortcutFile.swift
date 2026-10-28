import Foundation
import PaneCore

/// The shareable `.paneshortcuts` file: a small JSON envelope around the shortcut list.
///
///     { "format": "pane-shortcuts", "version": 1, "exportedAt": "2026-10-28T12:00:00Z",
///       "shortcuts": [ ...WindowShortcut... ] }
///
/// Older exports were a bare JSON array of shortcuts; those still decode.
enum ShortcutFile {
    static let format = "pane-shortcuts"
    static let currentVersion = 1
    static let fileExtension = "paneshortcuts"
    static let typeIdentifier = "com.karunpai.pane.shortcuts"
    static let defaultExportName = "My Pane Shortcuts.\(fileExtension)"

    struct Envelope: Codable, Equatable {
        var format: String
        var version: Int
        var exportedAt: Date
        var shortcuts: [WindowShortcut]
    }

    enum DecodeError: LocalizedError, Equatable {
        case notAShortcutsFile
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notAShortcutsFile:
                return "This file isn’t a Pane shortcuts file."
            case let .unsupportedVersion(version):
                return "This shortcuts file was made by a newer version of Pane (format version \(version)). Update Pane and try again."
            }
        }
    }

    static func encode(_ shortcuts: [WindowShortcut], exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let envelope = Envelope(format: format, version: currentVersion, exportedAt: exportedAt, shortcuts: shortcuts)
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> [WindowShortcut] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Legacy export: a plain array of shortcuts.
        if let legacy = try? decoder.decode([WindowShortcut].self, from: data) {
            return legacy
        }

        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? decoder.decode(Header.self, from: data),
              header.format == format,
              let version = header.version else {
            throw DecodeError.notAShortcutsFile
        }
        guard version <= currentVersion else { throw DecodeError.unsupportedVersion(version) }
        do {
            return try decoder.decode(Envelope.self, from: data).shortcuts
        } catch {
            throw DecodeError.notAShortcutsFile
        }
    }
}

enum ShortcutImportMode: Equatable {
    case merge
    case replace
}

struct ShortcutImportResult: Equatable {
    /// The full list that should be persisted.
    var shortcuts: [WindowShortcut]
    /// Number of imported shortcuts that were added to the list.
    var addedCount: Int
    /// Number of imported shortcuts skipped because an identical one already exists.
    var skippedDuplicateCount: Int
    /// Names (as stored) of imported shortcuts that were disabled because their key combination
    /// was already in use by another shortcut or by the panel shortcut.
    var disabledForConflict: [String]
    /// Imported shortcuts that were renamed because the name was already taken: (original, new).
    var renamed: [Renamed]

    struct Renamed: Equatable {
        var from: String
        var to: String
    }
}

/// Pure merge/replace planning. Never fails on key conflicts: conflicting imported shortcuts are
/// kept but disabled, so the resulting list always passes `ShortcutConflictValidator`.
enum ShortcutImportPlanner {
    static func plan(existing: [WindowShortcut], imported: [WindowShortcut],
                     mode: ShortcutImportMode, panel: PanelShortcut) -> ShortcutImportResult {
        var result = ShortcutImportResult(shortcuts: mode == .merge ? existing : [],
                                          addedCount: 0, skippedDuplicateCount: 0,
                                          disabledForConflict: [], renamed: [])
        var usedCombinations = Set<ShortcutConflictValidator.Combination>()
        if panel.isEnabled {
            usedCombinations.insert(.init(keyCode: panel.keyCode, modifiers: panel.cocoaModifiers))
        }
        for shortcut in result.shortcuts where shortcut.isEnabled && shortcut.isGlobal {
            usedCombinations.insert(.init(shortcut))
        }
        var usedIDs = Set(result.shortcuts.map(\.id))
        var usedNames = Set(result.shortcuts.map { $0.name.lowercased() })

        for original in imported {
            if mode == .merge, result.shortcuts.contains(where: { isSameContent($0, original) }) {
                result.skippedDuplicateCount += 1
                continue
            }
            var shortcut = original
            if usedIDs.contains(shortcut.id) { shortcut.id = UUID() }

            if mode == .merge, usedNames.contains(shortcut.name.lowercased()) {
                let newName = uniqueName(for: shortcut.name, taken: usedNames)
                result.renamed.append(.init(from: shortcut.name, to: newName))
                shortcut.name = newName
            }

            if shortcut.isEnabled && shortcut.isGlobal {
                let combination = ShortcutConflictValidator.Combination(shortcut)
                if usedCombinations.contains(combination) {
                    shortcut.isEnabled = false
                    result.disabledForConflict.append(shortcut.name)
                } else {
                    usedCombinations.insert(combination)
                }
            }

            usedIDs.insert(shortcut.id)
            usedNames.insert(shortcut.name.lowercased())
            result.shortcuts.append(shortcut)
            result.addedCount += 1
        }
        return result
    }

    /// Same shortcut apart from its identifier.
    static func isSameContent(_ lhs: WindowShortcut, _ rhs: WindowShortcut) -> Bool {
        var rhs = rhs
        rhs.id = lhs.id
        return lhs == rhs
    }

    private static func uniqueName(for name: String, taken: Set<String>) -> String {
        var candidate = "\(name) (Imported)"
        var counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(name) (Imported \(counter))"
            counter += 1
        }
        return candidate
    }
}
