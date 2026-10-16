// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bento",
    platforms: [.macOS(.v15)],
    products: [.library(name: "BentoCore", targets: ["BentoCore"]), .executable(name: "Bento", targets: ["BentoMac"])],
    targets: [
        .target(name: "BentoCore"),
        .executableTarget(name: "BentoMac", dependencies: ["BentoCore"], resources: [.process("Resources")]),
        .testTarget(name: "BentoCoreTests", dependencies: ["BentoCore"])
    ],
    swiftLanguageModes: [.v5]
)
