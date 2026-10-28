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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
