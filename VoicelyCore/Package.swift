// swift-tools-version:5.8
import PackageDescription

// Note: the XCTest target (VoicelyCoreTests) runs under full Xcode (`swift test`).
let package = Package(
    name: "VoicelyCore",
    products: [
        .library(name: "VoicelyCore", targets: ["VoicelyCore"]),
    ],
    targets: [
        .target(name: "VoicelyCore"),
        .testTarget(name: "VoicelyCoreTests", dependencies: ["VoicelyCore"]),
    ]
)
