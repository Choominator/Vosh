// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Vosh",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Vosh", targets: ["AccessibilityConsumer"])],
    targets: [.executableTarget(name: "AccessibilityConsumer")]
)
