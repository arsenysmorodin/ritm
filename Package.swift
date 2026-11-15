// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RitmCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "RitmCore", targets: ["RitmCore"])],
    targets: [
        .target(name: "RitmCore", path: "App/Core"),
        .testTarget(name: "RitmCoreTests", dependencies: ["RitmCore"], path: "Tests", exclude: ["run.sh"])
    ],
    swiftLanguageModes: [.v5]
)
