// swift-tools-version:5.9
import PackageDescription
import Foundation

// Check if building for direct distribution (includes Sparkle for auto-updates)
// Set VOICEY_DIRECT=1 environment variable when building direct distribution
let isDirectDistribution = ProcessInfo.processInfo.environment["VOICEY_DIRECT"] == "1"

// Base dependencies (always included)
var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
]

// macOS app target dependencies
var macOSTargetDependencies: [Target.Dependency] = [
    "VoiceyCore",
    "KeyboardShortcuts"
]

// Add Sparkle only for direct distribution builds
if isDirectDistribution {
    packageDependencies.append(
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    )
    macOSTargetDependencies.append("Sparkle")
}

let package = Package(
    name: "Voicey",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "VoiceyCore", targets: ["VoiceyCore"]),
        .executable(name: "Voicey", targets: ["Voicey"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "VoiceyCore",
            dependencies: ["WhisperKit"],
            path: "Sources/VoiceyCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("CoreML")
            ]
        ),
        .executableTarget(
            name: "Voicey",
            dependencies: macOSTargetDependencies,
            path: "Sources/Voicey",
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)
