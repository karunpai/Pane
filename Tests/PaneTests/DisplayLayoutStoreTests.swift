import XCTest
import PaneCore
@testable import Pane

final class DisplayLayoutStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: DisplayLayoutStore!

    override func setUpWithError() throws {
        suiteName = "com.karunpai.Pane.PaneDisplayLayoutTests"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = DisplayLayoutStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        CFPreferencesAppSynchronize(suiteName as CFString)
        try? FileManager.default.removeItem(at: plist)
        defaults = nil
        store = nil
    }

    func testFreshStoreHasDefaultsAndIsEnabled() {
        XCTAssertEqual(store.layouts, DisplayLayout.defaults)
        XCTAssertTrue(store.isEnabled)
    }

    func testSaveAndReload() throws {
        var layouts = DisplayLayout.defaults
        layouts.append(DisplayLayout(name: "Mac right", trigger: .control, position: .right, alignment: .center, menuBar: .monitor))
        try store.save(layouts)
        XCTAssertEqual(DisplayLayoutStore(defaults: defaults).layouts, layouts)
        XCTAssertEqual(store.layout(for: .control)?.name, "Mac right")
    }

    func testDuplicateTriggerRejectedAndNothingSaved() {
        var layouts = DisplayLayout.defaults
        layouts[1].trigger = .option
        XCTAssertThrowsError(try store.save(layouts)) { error in
            XCTAssertEqual(error as? DisplayLayoutStore.SaveError, .duplicateTrigger(.option))
        }
        XCTAssertEqual(store.layouts, DisplayLayout.defaults)
    }

    func testEmptyNameRejected() {
        var layouts = DisplayLayout.defaults
        layouts[0].name = "  "
        XCTAssertThrowsError(try store.save(layouts))
    }

    func testDeletingAllLayoutsIsAllowed() throws {
        try store.save([])
        XCTAssertEqual(store.layouts, [])
    }

    func testDisableSwitchPersists() {
        store.isEnabled = false
        XCTAssertFalse(DisplayLayoutStore(defaults: defaults).isEnabled)
    }

    func testSummaries() {
        XCTAssertEqual(DisplayLayout.defaults[0].summary, "Left of monitor · bottom edges")
        XCTAssertEqual(DisplayLayout.defaults[1].summary, "Below monitor · centered")
    }
}
