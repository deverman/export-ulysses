// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "export-ulysses",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
    ],
    targets: [
        .executableTarget(name: "export-ulysses", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
    ]
)
