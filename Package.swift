// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Particle",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Particle",
            path: "Sources/Particle",
            resources: [.process("sounds"), .process("images")]
        )
    ]
)
