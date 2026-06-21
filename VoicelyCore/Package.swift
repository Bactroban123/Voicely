// swift-tools-version:5.8
import PackageDescription

// Note: the XCTest target (VoicelyCoreTests) runs under full Xcode (`swift test`).
// `voicely-spec` is a dependency-free runnable mirror so the same logic can be
// verified with `swift run voicely-spec` on Command Line Tools alone.
let package = Package(
    name: "VoicelyCore",
    products: [
        .library(name: "VoicelyCore", targets: ["VoicelyCore"]),
        .executable(name: "voicely-spec", targets: ["voicely-spec"]),
    ],
    targets: [
        .target(name: "VoicelyCore"),
        .executableTarget(name: "voicely-spec", dependencies: ["VoicelyCore"]),
        .testTarget(name: "VoicelyCoreTests", dependencies: ["VoicelyCore"]),
    ]
)
