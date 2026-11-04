// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PressIfMeta",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PressIfMeta", targets: ["PressIfMeta"]),
        .executable(name: "press-if-check", targets: ["PressIfCheck"]),
        .executable(name: "PressIfImageFixture", targets: ["PressIfImageFixture"])
    ],
    targets: [
        .target(name: "PressIfCore"),
        .target(name: "PressIfImaging", dependencies: ["PressIfCore"]),
        .executableTarget(name: "PressIfMeta", dependencies: ["PressIfCore", "PressIfImaging"]),
        .executableTarget(name: "PressIfCheck", dependencies: ["PressIfCore", "PressIfImaging"]),
        .executableTarget(name: "PressIfImageFixture"),
        .testTarget(name: "PressIfCoreTests", dependencies: ["PressIfCore", "PressIfImaging"])
    ],
    swiftLanguageModes: [.v5]
)
