// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CmdDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CmdDock",
            path: "Sources/CmdDock",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
