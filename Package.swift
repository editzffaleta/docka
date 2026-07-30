// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Docka",
    platforms: [.macOS(.v14)],
    targets: [
        // Lógica pura (geometria da bandeja, curva de ampliação, varredura de apps).
        // Sem SwiftUI e sem AppKit — é o que os testes conseguem exercitar.
        .target(name: "DockaCore"),
        .executableTarget(name: "Docka",
                          dependencies: ["DockaCore"],
                          path: "Sources/Docka",
                          resources: [.copy("Assets")]),
        .testTarget(name: "DockaCoreTests", dependencies: ["DockaCore"])
    ]
)
