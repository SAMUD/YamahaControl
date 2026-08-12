// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YamahaAVRControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "YamahaAVRControl",
            path: "Sources/YamahaAVRControl"
        )
    ]
)
