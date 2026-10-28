// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Pane",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pane", targets: ["Pane"]),
        .library(name: "PaneCore", targets: ["PaneCore"])
    ],
    targets: [
        .target(name: "PaneCore"),
        .executableTarget(
            name: "Pane",
            dependencies: ["PaneCore"],
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(name: "GridLayoutCheck", dependencies: ["PaneCore"]),
        .testTarget(
            name: "PaneTests",
            dependencies: ["Pane", "PaneCore"]
        )
    ]
)
