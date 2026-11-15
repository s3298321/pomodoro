// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pomodoro", targets: ["Pomodoro"])
    ],
    targets: [
        .target(
            name: "PomodoroKit",
            path: "Pomodoro"
        ),
        .executableTarget(
            name: "Pomodoro",
            dependencies: ["PomodoroKit"],
            path: "PomodoroApp"
        ),
        .testTarget(
            name: "PomodoroTests",
            dependencies: ["PomodoroKit"],
            path: "PomodoroTests"
        ),
    ]
)
