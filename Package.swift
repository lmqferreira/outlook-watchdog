// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "outlook-watchdog",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "OutlookWatchdogLib",
            path: "Sources/Lib"
        ),
        .executableTarget(
            name: "outlook-watchdog",
            dependencies: ["OutlookWatchdogLib"],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "outlook-watchdog-tests",
            dependencies: ["OutlookWatchdogLib"],
            path: "Tests"
        )
    ]
)
