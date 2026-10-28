import Foundation
import PaneCore

struct PanelShortcut: Equatable {
    var isEnabled: Bool
    var keyCode: UInt32
    var cocoaModifiers: UInt
}

enum ShortcutValidationError: LocalizedError, Equatable {
    case conflictsWithPanel(shortcutName: String)
    case duplicateShortcut(firstName: String, secondName: String)

    var errorDescription: String? {
        switch self {
        case let .conflictsWithPanel(shortcutName):
            return "“\(shortcutName)” uses the shortcut assigned to show the Pane panel."
        case let .duplicateShortcut(firstName, secondName):
            return "“\(firstName)” and “\(secondName)” use the same global shortcut."
        }
    }
}

enum ShortcutConflictValidator {
    // Device-dependent and caps-lock bits must not make two otherwise identical
    // hot keys appear different.
    private static let supportedModifierMask: UInt = 0x001E0000

    static func validate(_ shortcuts: [WindowShortcut], panel: PanelShortcut) throws {
        var combinations: [Combination: String] = [:]
        let panelCombination = panel.isEnabled
            ? Combination(keyCode: panel.keyCode, modifiers: panel.cocoaModifiers)
            : nil

        for shortcut in shortcuts where shortcut.isEnabled && shortcut.isGlobal {
            let combination = Combination(keyCode: shortcut.keyCode, modifiers: shortcut.cocoaModifiers)
            if combination == panelCombination {
                throw ShortcutValidationError.conflictsWithPanel(shortcutName: shortcut.name)
            }
            if let existingName = combinations[combination] {
                throw ShortcutValidationError.duplicateShortcut(
                    firstName: existingName,
                    secondName: shortcut.name
                )
            }
            combinations[combination] = shortcut.name
        }
    }

    struct Combination: Hashable {
        let keyCode: UInt32
        let modifiers: UInt

        init(keyCode: UInt32, modifiers: UInt) {
            self.keyCode = keyCode
            self.modifiers = modifiers & ShortcutConflictValidator.supportedModifierMask
        }

        init(_ shortcut: WindowShortcut) {
            self.init(keyCode: shortcut.keyCode, modifiers: shortcut.cocoaModifiers)
        }
    }
}
