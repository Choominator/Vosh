// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Vosh",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Vosh", targets: ["Vosh"])],
    targets: [
        .executableTarget(
            name: "Vosh",
            dependencies: [
                .byName(name: "Element"),
                .byName(name: "Access"),
                .byName(name: "Input"),
                .byName(name: "Output")
            ]
        ),
        .target(
            name: "Access",
            dependencies: [
                .byName(name: "Input"),
                .byName(name: "Output"),
                .byName(name: "Element")
            ]
        ),
        .target(
            name: "Input",
            dependencies: [.byName(name: "Output")]
        ),
        .target(name: "Output"),
        .target(name: "Element")
    ]
)
