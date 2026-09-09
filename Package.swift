// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ruller",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ruller", targets: ["Ruller"])],
    targets: [
        .target(name: "RullerCore"),
        .executableTarget(name: "Ruller", dependencies: ["RullerCore"]),
        .testTarget(name: "RullerCoreTests", dependencies: ["RullerCore"])
    ]
)
