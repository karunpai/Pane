import CoreGraphics
import XCTest
import PaneCore

final class DisplayLayoutTests: XCTestCase {
    // The user's real hardware: MacBook (1512×982 pt) and a Samsung (3360×1890 pt).
    private let mac = CGSize(width: 1512, height: 982)
    private let monitor = CGSize(width: 3360, height: 1890)

    func testDefaultsAreTheTwoRequestedLayouts() {
        let defaults = DisplayLayout.defaults
        XCTAssertEqual(defaults.count, 2)
        XCTAssertEqual(defaults[0].name, "Mac on left")
        XCTAssertEqual(defaults[0].trigger, .option)
        XCTAssertEqual(defaults[0].position, .left)
        XCTAssertEqual(defaults[0].alignment, .end)
        XCTAssertEqual(defaults[0].menuBar, .mac)
        XCTAssertEqual(defaults[1].name, "Mac below")
        XCTAssertEqual(defaults[1].trigger, .command)
        XCTAssertEqual(defaults[1].position, .below)
        XCTAssertEqual(defaults[1].alignment, .center)
        XCTAssertEqual(defaults[1].menuBar, .mac)
    }

    func testMacOnLeftBottomAligned() {
        let origins = DisplayLayout.defaults[0].origins(mac: mac, monitor: monitor)
        XCTAssertEqual(origins.mac, CGPoint(x: 0, y: 0))
        XCTAssertEqual(origins.monitor, CGPoint(x: 1512, y: -908))
    }

    func testMacBelowCenteredMatchesCurrentArrangement() {
        // Matches what macOS reported for the user's "below" setup: monitor at (-924, -1890).
        let origins = DisplayLayout.defaults[1].origins(mac: mac, monitor: monitor)
        XCTAssertEqual(origins.mac, CGPoint(x: 0, y: 0))
        XCTAssertEqual(origins.monitor, CGPoint(x: -924, y: -1890))
    }

    func testRightAndAboveWithEdgeAlignments() {
        func monitorOrigin(_ position: MacPosition, _ alignment: LayoutAlignment) -> CGPoint {
            DisplayLayout(name: "x", trigger: .shift, position: position, alignment: alignment, menuBar: .mac)
                .origins(mac: mac, monitor: monitor).monitor
        }
        XCTAssertEqual(monitorOrigin(.right, .start), CGPoint(x: -3360, y: 0))
        XCTAssertEqual(monitorOrigin(.right, .center), CGPoint(x: -3360, y: -454))
        XCTAssertEqual(monitorOrigin(.above, .start), CGPoint(x: 0, y: 982))
        XCTAssertEqual(monitorOrigin(.above, .end), CGPoint(x: -1848, y: 982))
    }

    func testMenuBarOnMonitorPutsMonitorAtOrigin() {
        let layout = DisplayLayout(name: "x", trigger: .control, position: .below, alignment: .center, menuBar: .monitor)
        let origins = layout.origins(mac: mac, monitor: monitor)
        XCTAssertEqual(origins.monitor, CGPoint(x: 0, y: 0))
        XCTAssertEqual(origins.mac, CGPoint(x: 924, y: 1890))
    }

    func testOddSizesRoundToWholePoints() {
        let layout = DisplayLayout(name: "x", trigger: .option, position: .below, alignment: .center, menuBar: .mac)
        let origins = layout.origins(mac: CGSize(width: 1511, height: 982), monitor: CGSize(width: 2560, height: 1440))
        XCTAssertEqual(origins.monitor.x, origins.monitor.x.rounded())
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(DisplayLayout.defaults)
        XCTAssertEqual(try JSONDecoder().decode([DisplayLayout].self, from: data), DisplayLayout.defaults)
    }

    func testDuplicateTriggersAreRejected() {
        var layouts = DisplayLayout.defaults
        layouts[1].trigger = .option
        XCTAssertEqual(DisplayLayout.duplicateTriggers(in: layouts), [.option])
        XCTAssertEqual(DisplayLayout.duplicateTriggers(in: DisplayLayout.defaults), [])
    }
}

final class DoubleTapDetectorTests: XCTestCase {
    private var detector = DoubleTapDetector()

    override func setUp() { detector = DoubleTapDetector() }

    private func tap(_ key: DoubleTapKey, at time: TimeInterval) -> DoubleTapKey? {
        _ = detector.modifiersChanged([key], at: time)
        return detector.modifiersChanged([], at: time + 0.08)
    }

    func testTwoQuickTapsDetected() {
        XCTAssertNil(tap(.option, at: 0))
        XCTAssertEqual(tap(.option, at: 0.25), .option)
    }

    func testCommandDoubleTap() {
        XCTAssertNil(tap(.command, at: 10))
        XCTAssertEqual(tap(.command, at: 10.3), .command)
    }

    func testSlowTapsIgnored() {
        XCTAssertNil(tap(.option, at: 0))
        XCTAssertNil(tap(.option, at: 1.0))
    }

    func testDifferentKeysDoNotCombine() {
        XCTAssertNil(tap(.option, at: 0))
        XCTAssertNil(tap(.command, at: 0.2))
    }

    func testKeyPressInBetweenCancels() {
        // ⌘C then ⌘ again must not count as a double-tap.
        _ = detector.modifiersChanged([.command], at: 0)
        detector.keyPressed(at: 0.05)
        _ = detector.modifiersChanged([], at: 0.1)
        XCTAssertNil(tap(.command, at: 0.3))
    }

    func testHoldingTooLongIsNotATap() {
        _ = detector.modifiersChanged([.option], at: 0)
        _ = detector.modifiersChanged([], at: 0.8)
        XCTAssertNil(tap(.option, at: 1.0))
    }

    func testChordOfModifiersIsNotATap() {
        _ = detector.modifiersChanged([.option], at: 0)
        _ = detector.modifiersChanged([.option, .shift], at: 0.03)
        _ = detector.modifiersChanged([], at: 0.08)
        XCTAssertNil(tap(.option, at: 0.25))
    }

    func testTripleTapFiresOnce() {
        XCTAssertNil(tap(.option, at: 0))
        XCTAssertEqual(tap(.option, at: 0.2), .option)
        XCTAssertNil(tap(.option, at: 0.4))
    }
}
