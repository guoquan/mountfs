// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MountFS",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MountFS", targets: ["MountFSApp"])],
    targets: [.executableTarget(name: "MountFSApp", path: "Sources/MountFSApp")]
)
