import Foundation
import PaneCore
import XCTest
@testable import Pane

final class ShortcutPersistenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: ShortcutStore!
    private var preferences: AppPreferences!

    override func setUpWithError() throws {
        suiteName = "PaneTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = ShortcutStore(defaults: defaults)
        preferences = AppPreferences(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        preferences = nil
    }

    func testCreateEditAndDeletePersistAcrossStoreInstances() throws {
        var shortcut = makeShortcut(name: "Left", keyCode: 1)
        try store.replaceShortcuts([shortcut], panel: disabledPanel)
        XCTAssertEqual(ShortcutStore(defaults: defaults).shortcuts, [shortcut])

        let originalID = shortcut.id
        shortcut.name = "Left Two Thirds"
        shortcut.selection = GridSelection(startRow: 0, startColumn: 0, endRow: 5, endColumn: 3)
        try store.replaceShortcuts([shortcut], panel: disabledPanel)
        XCTAssertEqual(store.shortcuts.first?.id, originalID)
        XCTAssertEqual(store.shortcuts.first?.name, "Left Two Thirds")

        try store.replaceShortcuts([], panel: disabledPanel)
        XCTAssertTrue(ShortcutStore(defaults: defaults).shortcuts.isEmpty)
    }

    func testCancelledEditDoesNotPersistDraft() throws {
        let original = makeShortcut(name: "Saved", keyCode: 2)
        try store.replaceShortcuts([original], panel: disabledPanel)

        var draft = original
        draft.name = "Uncommitted edit"
        draft.keyCode = 3

        XCTAssertNotEqual(draft, original)
        XCTAssertEqual(store.shortcuts, [original])
    }

    func testDuplicateSaveFailsWithoutChangingPersistedShortcuts() throws {
        let original = makeShortcut(name: "Original", keyCode: 2)
        try store.replaceShortcuts([original], panel: disabledPanel)
        let conflict = makeShortcut(name: "Conflict", keyCode: 2)

        XCTAssertThrowsError(try store.replaceShortcuts([original, conflict], panel: disabledPanel)) { error in
            XCTAssertEqual(
                error as? ShortcutValidationError,
                .duplicateShortcut(firstName: "Original", secondName: "Conflict")
            )
        }
        XCTAssertEqual(store.shortcuts, [original])
    }

    func testInvalidMergeAndReplaceCandidatesPreserveAllExistingRecords() throws {
        let existing = (0..<23).map { makeShortcut(name: "Shortcut \($0)", keyCode: UInt32($0 + 10)) }
        try store.replaceShortcuts(existing, panel: disabledPanel)

        let mergeConflict = makeShortcut(name: "Merge Conflict", keyCode: existing[7].keyCode)
        XCTAssertThrowsError(try store.replaceShortcuts(existing + [mergeConflict], panel: disabledPanel))
        XCTAssertEqual(store.shortcuts.map(\.id), existing.map(\.id))

        let replaceConflict = [
            makeShortcut(name: "Replace A", keyCode: 90),
            makeShortcut(name: "Replace B", keyCode: 90)
        ]
        XCTAssertThrowsError(try store.replaceShortcuts(replaceConflict, panel: disabledPanel))
        XCTAssertEqual(store.shortcuts, existing)
    }

    func testPanelShortcutConflictIsAtomic() throws {
        let shortcut = makeShortcut(name: "Top", keyCode: 7)
        try store.replaceShortcuts([shortcut], panel: disabledPanel)
        let previous = preferences.panelShortcut

        XCTAssertThrowsError(
            try preferences.updatePanelShortcut(
                enabled: true,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.cocoaModifiers,
                validating: store.shortcuts
            )
        ) { error in
            XCTAssertEqual(
                error as? ShortcutValidationError,
                .conflictsWithPanel(shortcutName: "Top")
            )
        }
        XCTAssertEqual(preferences.panelShortcut, previous)

        try preferences.updatePanelShortcut(
            enabled: true,
            keyCode: 8,
            modifiers: shortcut.cocoaModifiers,
            validating: store.shortcuts
        )
        XCTAssertEqual(
            preferences.panelShortcut,
            PanelShortcut(isEnabled: true, keyCode: 8, cocoaModifiers: shortcut.cocoaModifiers)
        )
    }

    func testDisabledAndNonGlobalShortcutsDoNotConflict() throws {
        let active = makeShortcut(name: "Active", keyCode: 4)
        var disabled = makeShortcut(name: "Disabled", keyCode: 4)
        disabled.isEnabled = false
        var local = makeShortcut(name: "Stored", keyCode: 4)
        local.isGlobal = false

        XCTAssertNoThrow(try store.replaceShortcuts([active, disabled, local], panel: disabledPanel))
        XCTAssertEqual(store.shortcuts.count, 3)
    }

    private var disabledPanel: PanelShortcut {
        PanelShortcut(isEnabled: false, keyCode: 49, cocoaModifiers: 0x000C0000)
    }

    private func makeShortcut(name: String, keyCode: UInt32) -> WindowShortcut {
        WindowShortcut(
            name: name,
            keyCode: keyCode,
            cocoaModifiers: 0x00180000,
            isGlobal: true,
            isEnabled: true,
            rows: 6,
            columns: 6,
            isSubdivided: false,
            selection: GridSelection(startRow: 0, startColumn: 0, endRow: 5, endColumn: 2)
        )
    }
}
