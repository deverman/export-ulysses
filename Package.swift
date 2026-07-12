// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "export-ulysses",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "UlyssesExporter", targets: ["UlyssesExporter"]),
        .executable(name: "export-ulysses", targets: ["export-ulysses"]),
        .executable(name: "ExportUlyssesApp", targets: ["ExportUlyssesApp"]),
        .executable(name: "release-tool", targets: ["release-tool"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
    ],
    targets: [
        .target(name: "UlyssesExporter"),
        .executableTarget(name: "export-ulysses", dependencies: [
            "UlyssesExporter",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .executableTarget(
            name: "ExportUlyssesApp",
            dependencies: ["UlyssesExporter"],
            path: "Sources/ExportUlyssesApp"
        ),
        .target(name: "ReleaseToolKit"),
        .executableTarget(name: "release-tool", dependencies: [
            "ReleaseToolKit",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .testTarget(name: "UlyssesExporterTests", dependencies: ["UlyssesExporter"]),
        .testTarget(name: "ReleaseToolKitTests", dependencies: ["ReleaseToolKit"])
    ]
)
