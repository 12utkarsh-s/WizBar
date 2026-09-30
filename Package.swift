// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WizBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WizBar", path: "Sources/WizBar")
    ]
)
