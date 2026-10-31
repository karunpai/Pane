import Foundation
import PaneCore

/// Saved display layouts and the on/off switch for display arrangement.
final class DisplayLayoutStore {
    static let shared = DisplayLayoutStore()
    static let didChangeNotification = Notification.Name("Pane.displayLayoutsDidChange")

    enum SaveError: LocalizedError, Equatable {
        case duplicateTrigger(DoubleTapKey)
        case emptyName

        var errorDescription: String? {
            switch self {
            case .duplicateTrigger(let key):
                return "Two layouts use \(key.displayName) twice. Each layout needs its own key."
            case .emptyName:
                return "Every layout needs a name."
            }
        }
    }

    private enum Key {
        static let layouts = "displayLayouts.v1"
        static let enabled = "displayArrangementEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether Pane listens for double-taps after a monitor is connected. On by default.
    var isEnabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Key.enabled)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Saved layouts; the two defaults until the user changes them.
    var layouts: [DisplayLayout] {
        guard let data = defaults.data(forKey: Key.layouts),
              let decoded = try? JSONDecoder().decode([DisplayLayout].self, from: data) else {
            return DisplayLayout.defaults
        }
        return decoded
    }

    /// Validates and persists. On failure nothing is saved.
    func save(_ layouts: [DisplayLayout]) throws {
        if layouts.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw SaveError.emptyName
        }
        if let duplicate = DisplayLayout.duplicateTriggers(in: layouts).sorted(by: { $0.rawValue < $1.rawValue }).first {
            throw SaveError.duplicateTrigger(duplicate)
        }
        defaults.set(try JSONEncoder().encode(layouts), forKey: Key.layouts)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func layout(for trigger: DoubleTapKey) -> DisplayLayout? {
        layouts.first { $0.trigger == trigger }
    }
}

extension DoubleTapKey {
    /// "Option", "Command", …
    var displayName: String {
        switch self {
        case .option: return "Option"
        case .command: return "Command"
        case .control: return "Control"
        case .shift: return "Shift"
        }
    }

    /// "⌥ ⌥", "⌘ ⌘", …
    var symbolPair: String {
        let symbol: String
        switch self {
        case .option: symbol = "⌥"
        case .command: symbol = "⌘"
        case .control: symbol = "⌃"
        case .shift: symbol = "⇧"
        }
        return "\(symbol) \(symbol)"
    }
}

extension DisplayLayout {
    /// Short description such as "Left of monitor · bottom edges".
    var summary: String {
        let place: String
        switch position {
        case .left: place = "Left of monitor"
        case .right: place = "Right of monitor"
        case .above: place = "Above monitor"
        case .below: place = "Below monitor"
        }
        return "\(place) · \(alignment.label(for: position).lowercased())"
    }
}

extension LayoutAlignment {
    /// Label for this alignment given the Mac's position ("Top edges", "Centered", …).
    func label(for position: MacPosition) -> String {
        switch (self, position) {
        case (.center, _): return "Centered"
        case (.start, .left), (.start, .right): return "Top edges"
        case (.end, .left), (.end, .right): return "Bottom edges"
        case (.start, _): return "Left edges"
        case (.end, _): return "Right edges"
        }
    }
}
