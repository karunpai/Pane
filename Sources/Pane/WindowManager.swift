import AppKit
import ApplicationServices

final class WindowManager {
    struct Target {
        let app: NSRunningApplication
        let window: AXUIElement
    }

    private(set) var lastOperationFailure: String?

    func requestAccessibilityPermission(prompt: Bool = false) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    func captureFrontmostWindow() -> Target? {
        guard requestAccessibilityPermission(prompt: false) else { return nil }
        lastOperationFailure = nil
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            recordFailure("No external frontmost application is available.")
            return nil
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success else {
            recordFailure("Read focused window", error: result)
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            recordFailure("The frontmost application did not return a valid focused window.")
            return nil
        }
        return Target(app: app, window: unsafeBitCast(value, to: AXUIElement.self))
    }

    @discardableResult
    func move(_ target: Target, to appKitFrame: CGRect) -> Bool {
        guard requestAccessibilityPermission(prompt: false) else { return false }
        lastOperationFailure = nil
        let axFrame = convertToAXCoordinates(appKitFrame)
        var point = axFrame.origin
        var size = axFrame.size
        guard let positionValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            recordFailure("Could not create window position/size values.")
            return false
        }
        let sizeResult = AXUIElementSetAttributeValue(target.window, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(target.window, kAXPositionAttribute as CFString, positionValue)
        let retrySizeResult = AXUIElementSetAttributeValue(target.window, kAXSizeAttribute as CFString, sizeValue)
        let raiseResult = AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        if positionResult != .success { recordFailure("Set window position", error: positionResult) }
        if retrySizeResult != .success { recordFailure("Set window size", error: retrySizeResult) }
        if raiseResult != .success { recordFailure("Raise window", error: raiseResult) }
        target.app.activate(options: [])
        return positionResult == .success && (sizeResult == .success || retrySizeResult == .success)
    }

    func screen(containing target: Target) -> NSScreen? {
        guard requestAccessibilityPermission(prompt: false) else { return nil }
        var positionObject: CFTypeRef?
        var sizeObject: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(target.window, kAXPositionAttribute as CFString, &positionObject)
        let sizeResult = AXUIElementCopyAttributeValue(target.window, kAXSizeAttribute as CFString, &sizeObject)
        guard positionResult == .success, sizeResult == .success else {
            if positionResult != .success { recordFailure("Read window position", error: positionResult) }
            if sizeResult != .success { recordFailure("Read window size", error: sizeResult) }
            return nil
        }
        guard let positionObject, let sizeObject,
              CFGetTypeID(positionObject) == AXValueGetTypeID(),
              CFGetTypeID(sizeObject) == AXValueGetTypeID() else {
            recordFailure("The window returned invalid position/size attributes.")
            return nil
        }
        let positionValue = unsafeBitCast(positionObject, to: AXValue.self)
        let sizeValue = unsafeBitCast(sizeObject, to: AXValue.self)
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size) else {
            recordFailure("Could not decode window position/size attributes.")
            return nil
        }
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitFrame = CGRect(x: point.x, y: mainTop - point.y - size.height, width: size.width, height: size.height)
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(appKitFrame).area < rhs.frame.intersection(appKitFrame).area
        }
    }

    private func recordFailure(_ message: String, error: AXError? = nil) {
        let diagnostic = error.map { "\(message): AXError \($0.rawValue)" } ?? message
        if let previous = lastOperationFailure {
            lastOperationFailure = previous + "\n" + diagnostic
        } else {
            lastOperationFailure = diagnostic
        }
        NSLog("Pane window operation: %@; Accessibility trusted: %@", diagnostic,
              AXIsProcessTrusted() ? "yes" : "no")
    }

    private func convertToAXCoordinates(_ frame: CGRect) -> CGRect {
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: mainTop - frame.maxY, width: frame.width, height: frame.height)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
