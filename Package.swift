// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreeDViewer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ThreeDViewer",
            path: "Sources/ThreeDViewer"
        )
    ]
)
