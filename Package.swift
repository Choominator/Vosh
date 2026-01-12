// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Vosh",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Vosh", targets: ["Vosh"])],
    targets: [
        .executableTarget(
            name: "Vosh",
            dependencies: [
                .target(name: "Access"),
                .target(name: "Input"),
                .target(name: "Output")
            ]
        ),
        .target(
            name: "Access",
            dependencies: [
                .target(name: "Input"),
                .target(name: "Output"),
                .target(name: "Element")
            ]
        ),
        .target(
            name: "Input",
            dependencies: [.target(name: "Output")]
        ),
        .target(name: "Output"),
        .target(name: "Element")
    ]
)
