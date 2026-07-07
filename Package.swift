// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Docka",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Docka", path: "Sources/Docka")
    ]
)
