// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Copiste",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Copiste", path: "Sources/Copiste")
    ]
)
