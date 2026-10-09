// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MountFS",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MountFS", targets: ["MountFSApp"])],
    targets: [
        .target(name: "MountFSCore"),
        .executableTarget(name: "MountFSApp", dependencies: ["MountFSCore"], path: "Sources/MountFSApp"),
        .testTarget(name: "MountFSCoreTests", dependencies: ["MountFSCore"])
    ]
)
