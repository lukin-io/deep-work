// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepWork",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "DeepWorkCore", targets: ["DeepWorkCore"]),
        .executable(name: "DeepWork", targets: ["DeepWorkApp"])
    ],
    targets: [
        .target(name: "DeepWorkCore", path: "DeepWork", exclude: ["App", "Features", "Resources"]),
        .executableTarget(name: "DeepWorkApp", dependencies: ["DeepWorkCore"], path: "DeepWork", exclude: ["Core", "Data", "Resources"]),
        .testTarget(name: "DeepWorkCoreTests", dependencies: ["DeepWorkCore"], path: "DeepWorkTests/Core"),
        .testTarget(name: "DeepWorkAppTests", dependencies: ["DeepWorkApp", "DeepWorkCore"], path: "DeepWorkTests/App")
    ]
)
