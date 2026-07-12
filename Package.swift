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
        .executable(name: "ExportUlyssesApp", targets: ["ExportUlyssesApp"])
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
        .testTarget(name: "UlyssesExporterTests", dependencies: ["UlyssesExporter"])
    ]
)
