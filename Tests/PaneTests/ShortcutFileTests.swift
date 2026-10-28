import Foundation
import PaneCore
import XCTest
@testable import Pane

final class ShortcutFileTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: ShortcutStore!

    override func setUpWithError() throws {
        suiteName = "PaneShortcutFileTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = ShortcutStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        // removePersistentDomain leaves an empty plist behind; delete it too.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
        defaults = nil
        store = nil
    }

    // MARK: - Format

    func testRoundTripPreservesShortcutsAndEnvelope() throws {
        let shortcuts = [make("Left", keyCode: 1), make("Right", keyCode: 2, subdivided: true)]
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try ShortcutFile.encode(shortcuts, exportedAt: date)

        XCTAssertEqual(try ShortcutFile.decode(data), shortcuts)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "pane-shortcuts")
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["exportedAt"] as? String, "2027-01-15T08:00:00Z")
        XCTAssertEqual((json["shortcuts"] as? [Any])?.count, 2)
    }

    func testLegacyPlainArrayStillDecodes() throws {
        let shortcuts = [make("Legacy", keyCode: 5)]
        let legacy = try JSONEncoder().encode(shortcuts)
        XCTAssertEqual(try ShortcutFile.decode(legacy), shortcuts)
    }

    func testRejectsForeignAndFutureFiles() {
        XCTAssertThrowsError(try ShortcutFile.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? ShortcutFile.DecodeError, .notAShortcutsFile)
        }
        XCTAssertThrowsError(try ShortcutFile.decode(Data(#"{"format":"other","version":1,"shortcuts":[]}"#.utf8))) {
            XCTAssertEqual($0 as? ShortcutFile.DecodeError, .notAShortcutsFile)
        }
        XCTAssertThrowsError(try ShortcutFile.decode(Data(#"{"format":"pane-shortcuts","version":99,"exportedAt":"2026-01-01T00:00:00Z","shortcuts":[]}"#.utf8))) {
            XCTAssertEqual($0 as? ShortcutFile.DecodeError, .unsupportedVersion(99))
        }
    }

    // MARK: - Merge / replace

    func testMergeSkipsExactDuplicatesAndAddsNewOnes() throws {
        let existing = [make("Left", keyCode: 1), make("Right", keyCode: 2)]
        try store.replaceShortcuts(existing, panel: disabledPanel)

        var duplicateWithOtherID = existing[0]
        duplicateWithOtherID.id = UUID()
        let new = make("Top", keyCode: 3)
        let file = try ShortcutFile.encode([existing[1], duplicateWithOtherID, new])

        let result = try store.importFile(file, mode: .merge, panel: disabledPanel)
        XCTAssertEqual(result.skippedDuplicateCount, 2)
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertTrue(result.disabledForConflict.isEmpty)
        XCTAssertEqual(store.shortcuts, existing + [new])
    }

    func testMergeDisablesKeyConflictsInsteadOfFailing() throws {
        let existing = [make("Left", keyCode: 1)]
        try store.replaceShortcuts(existing, panel: enabledPanel)

        let clashesWithExisting = make("Other Left", keyCode: 1)
        let clashesWithPanel = make("Panel Clash", keyCode: enabledPanel.keyCode, modifiers: enabledPanel.cocoaModifiers)
        let sameName = make("Left", keyCode: 9)
        let fine = make("Bottom", keyCode: 4)
        let file = try ShortcutFile.encode([clashesWithExisting, clashesWithPanel, sameName, fine])

        let result = try store.importFile(file, mode: .merge, panel: enabledPanel)
        XCTAssertEqual(result.addedCount, 4)
        XCTAssertEqual(result.disabledForConflict, ["Other Left", "Panel Clash"])
        XCTAssertEqual(result.renamed, [.init(from: "Left", to: "Left (Imported)")])

        let stored = store.shortcuts
        XCTAssertEqual(stored.count, 5)
        XCTAssertEqual(stored[0], existing[0], "existing shortcuts are untouched")
        XCTAssertFalse(try XCTUnwrap(stored.first { $0.name == "Other Left" }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(stored.first { $0.name == "Panel Clash" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(stored.first { $0.name == "Left (Imported)" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(stored.first { $0.name == "Bottom" }).isEnabled)
        XCTAssertNoThrow(try ShortcutConflictValidator.validate(stored, panel: enabledPanel))
    }

    func testMergeReassignsCollidingIDsForChangedShortcuts() throws {
        let original = make("Left", keyCode: 1)
        try store.replaceShortcuts([original], panel: disabledPanel)
        var edited = original
        edited.selection = GridSelection(startRow: 0, startColumn: 0, endRow: 1, endColumn: 1)
        edited.name = "Left Corner"

        try store.importFile(try ShortcutFile.encode([edited]), mode: .merge, panel: disabledPanel)
        let stored = store.shortcuts
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(Set(stored.map(\.id)).count, 2)
        XCTAssertFalse(stored[1].isEnabled, "same key as the original, so imported disabled")
    }

    func testReplaceSwapsTheWholeList() throws {
        try store.replaceShortcuts((0..<23).map { make("Old \($0)", keyCode: UInt32($0 + 10)) }, panel: disabledPanel)
        let incoming = [make("New A", keyCode: 1), make("New B", keyCode: 1)]

        let result = try store.importFile(try ShortcutFile.encode(incoming), mode: .replace, panel: disabledPanel)
        XCTAssertEqual(result.addedCount, 2)
        XCTAssertEqual(result.disabledForConflict, ["New B"])
        XCTAssertEqual(store.shortcuts.map(\.name), ["New A", "New B"])
        XCTAssertEqual(store.shortcuts.map(\.isEnabled), [true, false])
    }

    func testBadFileLeavesStoreUnchanged() throws {
        let existing = (0..<23).map { make("Shortcut \($0)", keyCode: UInt32($0 + 10)) }
        try store.replaceShortcuts(existing, panel: disabledPanel)

        for mode in [ShortcutImportMode.merge, .replace] {
            XCTAssertThrowsError(try store.importFile(Data("{ broken".utf8), mode: mode, panel: disabledPanel))
            XCTAssertThrowsError(try store.importFile(Data(#"{"format":"pane-shortcuts","version":1}"#.utf8), mode: mode, panel: disabledPanel))
            XCTAssertEqual(store.shortcuts, existing)
        }
    }

    func testExportFileDataContainsStoredShortcuts() throws {
        let existing = [make("Left", keyCode: 1)]
        try store.replaceShortcuts(existing, panel: disabledPanel)
        XCTAssertEqual(try ShortcutFile.decode(try store.exportFileData()), existing)
    }

    func testFreshStoreHasNoShortcuts() {
        XCTAssertTrue(store.shortcuts.isEmpty)
    }

    /// Optional check of a real exported file: set PANE_SHORTCUTS_FILE to its path.
    func testDecodesFileFromEnvironmentWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["PANE_SHORTCUTS_FILE"] else {
            throw XCTSkip("PANE_SHORTCUTS_FILE not set")
        }
        let shortcuts = try ShortcutFile.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        if let expected = ProcessInfo.processInfo.environment["PANE_SHORTCUTS_EXPECTED_COUNT"].flatMap(Int.init) {
            XCTAssertEqual(shortcuts.count, expected)
        }
        XCTAssertNoThrow(try ShortcutConflictValidator.validate(shortcuts, panel: disabledPanel))
    }

    // MARK: - Helpers

    private var disabledPanel: PanelShortcut {
        PanelShortcut(isEnabled: false, keyCode: 49, cocoaModifiers: 0x000C0000)
    }

    private var enabledPanel: PanelShortcut {
        PanelShortcut(isEnabled: true, keyCode: 49, cocoaModifiers: 0x000C0000)
    }

    private func make(_ name: String, keyCode: UInt32, modifiers: UInt = 0x00180000,
                      subdivided: Bool = false) -> WindowShortcut {
        WindowShortcut(
            name: name, keyCode: keyCode, cocoaModifiers: modifiers,
            isGlobal: true, isEnabled: true, rows: 6, columns: 6, isSubdivided: subdivided,
            selection: GridSelection(startRow: 0, startColumn: 0, endRow: 5, endColumn: 2)
        )
    }
}
