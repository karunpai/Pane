import AppKit

@main
@MainActor
struct PaneMain {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-overlay") {
            let arguments = CommandLine.arguments
            let directory = index + 1 < arguments.count ? arguments[index + 1] : FileManager.default.currentDirectoryPath
            exit(OverlaySnapshot.run(outputDirectory: directory))
        }
        // `Pane --apply-layout "Mac below"` applies a saved display layout and exits.
        if let index = CommandLine.arguments.firstIndex(of: "--apply-layout") {
            let arguments = CommandLine.arguments
            let name = index + 1 < arguments.count ? arguments[index + 1] : ""
            guard let layout = DisplayLayoutStore.shared.layouts.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                print("No display layout named \"\(name)\". Saved layouts: \(DisplayLayoutStore.shared.layouts.map(\.name).joined(separator: ", "))")
                exit(1)
            }
            let outcome = DisplayArranger.apply(layout)
            print(outcome.problem ?? "Applied \"\(layout.name)\".")
            exit(outcome == .applied ? 0 : 1)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
