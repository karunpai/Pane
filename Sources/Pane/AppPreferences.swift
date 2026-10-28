import Foundation
import PaneCore

final class AppPreferences {
    static let shared = AppPreferences()
    static let didChangeNotification = Notification.Name("Pane.preferencesDidChange")
    static let shortcutsDidChangeNotification = Notification.Name("Pane.shortcutsDidChange")
    static let hotKeyRecordingDidBeginNotification = Notification.Name("Pane.hotKeyRecordingDidBegin")
    static let hotKeyRecordingDidEndNotification = Notification.Name("Pane.hotKeyRecordingDidEnd")
    static let hotKeyRegistrationFailuresNotification = Notification.Name("Pane.hotKeyRegistrationFailures")
    /// Posted by the grid overlay's back side ("Settings…") to ask the app to open the full settings window.
    static let openSettingsRequestedNotification = Notification.Name("Pane.openSettingsRequested")
    private let defaults: UserDefaults

    private enum Key {
        static let rows = "gridRows"
        static let columns = "gridColumns"
        static let horizontalGap = "windowGapWidth"
        static let verticalGap = "windowGapHeight"
        static let marginLeft = "screenMarginLeft"
        static let marginRight = "screenMarginRight"
        static let marginTop = "screenMarginTop"
        static let marginBottom = "screenMarginBottom"
        static let marginsEnabled = "marginsEnabled"
        static let keepOpen = "keepPanelOpen"
        static let showPreview = "showResizePreview"
        static let cycleDisplays = "cycleDisplays"
        static let showMenuBar = "showMenuBar"
        static let panelShortcutEnabled = "panelShortcutEnabled"
        static let panelShortcutKeyCode = "panelShortcutKeyCode"
        static let panelShortcutModifiers = "panelShortcutModifiers"
        // "Use these settings on activation" (useDefaultGrid / defaultRowCount / defaultColumnCount).
        static let useDefaultGrid = "useDefaultGrid"
        static let defaultRows = "defaultRowCount"
        static let defaultColumns = "defaultColumnCount"
        static let animationsEnabled = "enableAnimations"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.rows: 10, Key.columns: 10,
            Key.horizontalGap: 16.0, Key.verticalGap: 16.0,
            Key.marginLeft: 5.0, Key.marginRight: 5.0, Key.marginTop: 5.0, Key.marginBottom: 5.0,
            Key.marginsEnabled: true,
            Key.keepOpen: false, Key.showPreview: true, Key.cycleDisplays: false,
            Key.showMenuBar: true, Key.panelShortcutEnabled: true,
            Key.panelShortcutKeyCode: 49, // Space
            Key.panelShortcutModifiers: 786432, // Control + Option in NSEvent.ModifierFlags
            Key.useDefaultGrid: false, Key.defaultRows: 10, Key.defaultColumns: 10,
            Key.animationsEnabled: true
        ])
    }

    var rows: Int { get { defaults.integer(forKey: Key.rows) } set { set(max(1, min(10, newValue)), for: Key.rows) } }
    var columns: Int { get { defaults.integer(forKey: Key.columns) } set { set(max(1, min(10, newValue)), for: Key.columns) } }
    var horizontalGap: Double { get { defaults.double(forKey: Key.horizontalGap) } set { set(max(0, min(300, newValue)), for: Key.horizontalGap) } }
    var verticalGap: Double { get { defaults.double(forKey: Key.verticalGap) } set { set(max(0, min(300, newValue)), for: Key.verticalGap) } }
    var marginLeft: Double { get { defaults.double(forKey: Key.marginLeft) } set { set(max(0, min(300, newValue)), for: Key.marginLeft) } }
    var marginRight: Double { get { defaults.double(forKey: Key.marginRight) } set { set(max(0, min(300, newValue)), for: Key.marginRight) } }
    var marginTop: Double { get { defaults.double(forKey: Key.marginTop) } set { set(max(0, min(300, newValue)), for: Key.marginTop) } }
    var marginBottom: Double { get { defaults.double(forKey: Key.marginBottom) } set { set(max(0, min(300, newValue)), for: Key.marginBottom) } }
    var marginsEnabled: Bool { get { defaults.bool(forKey: Key.marginsEnabled) } set { set(newValue, for: Key.marginsEnabled) } }
    var keepOpen: Bool { get { defaults.bool(forKey: Key.keepOpen) } set { set(newValue, for: Key.keepOpen) } }
    var showPreview: Bool { get { defaults.bool(forKey: Key.showPreview) } set { set(newValue, for: Key.showPreview) } }
    var cycleDisplays: Bool { get { defaults.bool(forKey: Key.cycleDisplays) } set { set(newValue, for: Key.cycleDisplays) } }
    var showMenuBar: Bool { get { defaults.bool(forKey: Key.showMenuBar) } set { set(newValue, for: Key.showMenuBar) } }
    /// When true the overlay resets the grid to `defaultRows` × `defaultColumns` each time it opens.
    var useDefaultGrid: Bool { get { defaults.bool(forKey: Key.useDefaultGrid) } set { set(newValue, for: Key.useDefaultGrid) } }
    var defaultRows: Int { get { defaults.integer(forKey: Key.defaultRows) } set { set(max(1, min(10, newValue)), for: Key.defaultRows) } }
    var defaultColumns: Int { get { defaults.integer(forKey: Key.defaultColumns) } set { set(max(1, min(10, newValue)), for: Key.defaultColumns) } }
    /// Overlay fade and card-flip animations.
    var animationsEnabled: Bool { get { defaults.bool(forKey: Key.animationsEnabled) } set { set(newValue, for: Key.animationsEnabled) } }
    var panelShortcutEnabled: Bool { defaults.bool(forKey: Key.panelShortcutEnabled) }
    var panelShortcutKeyCode: UInt32 { UInt32(defaults.integer(forKey: Key.panelShortcutKeyCode)) }
    var panelShortcutModifiers: UInt { UInt(defaults.integer(forKey: Key.panelShortcutModifiers)) }
    var panelShortcut: PanelShortcut {
        PanelShortcut(
            isEnabled: panelShortcutEnabled,
            keyCode: panelShortcutKeyCode,
            cocoaModifiers: panelShortcutModifiers
        )
    }

    func updatePanelShortcut(
        enabled: Bool,
        keyCode: UInt32,
        modifiers: UInt,
        validating shortcuts: [WindowShortcut]
    ) throws {
        let candidate = PanelShortcut(isEnabled: enabled, keyCode: keyCode, cocoaModifiers: modifiers)
        try ShortcutConflictValidator.validate(shortcuts, panel: candidate)
        defaults.set(enabled, forKey: Key.panelShortcutEnabled)
        defaults.set(Int(keyCode), forKey: Key.panelShortcutKeyCode)
        defaults.set(Int(modifiers), forKey: Key.panelShortcutModifiers)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
