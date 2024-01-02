// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Vosh",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Vosh", targets: ["Entry"])],
    targets: [
        .executableTarget(
            name: "Entry",
            dependencies: [
                .byName(name: "Input"),
                .byName(name: "Output"),
                .byName(name: "Consumer")
            ]
        ),
        .target(name: "Input"),
        .target(name: "Output", dependencies: [.byName(name: "Consumer")]),
        .target(name: "Consumer")
    ]
)
