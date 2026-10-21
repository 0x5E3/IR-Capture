// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IRCapture",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IRCaptureCore", targets: ["IRCaptureCore"]),
        .executable(name: "ircapture-cli", targets: ["ircapture-cli"]),
        .executable(name: "IRCaptureApp", targets: ["IRCaptureApp"]),
    ],
    targets: [
        // The DSP. Plain Swift + Foundation so it also builds and tests on Linux.
        .target(name: "IRCaptureCore",
                swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]),
        // Command-line front end, used by the golden test against the Python reference.
        .executableTarget(name: "ircapture-cli", dependencies: ["IRCaptureCore"]),
        // The Mac app (SwiftUI + CoreAudio). On other platforms it builds to a stub.
        .executableTarget(name: "IRCaptureApp", dependencies: ["IRCaptureCore"]),
        .testTarget(name: "IRCaptureCoreTests", dependencies: ["IRCaptureCore"]),
    ]
)
