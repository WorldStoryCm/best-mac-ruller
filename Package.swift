// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ruller",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ruller", targets: ["Ruller"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "RullerCore"),
        .executableTarget(name: "Ruller", dependencies: ["RullerCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "RullerCoreTests", dependencies: ["RullerCore"])
    ]
)
