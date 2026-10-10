// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MountFS",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MountFS", targets: ["MountFSApp"]),
               .executable(name: "MountFSIdentity", targets: ["MountFSIdentity"]),
               .executable(name: "MountFSHelper", targets: ["MountFSHelper"])],
    targets: [
        .target(name: "MountFSCore"),
        .target(name: "MountFSPrivileged"),
        .executableTarget(name: "MountFSHelper", dependencies: ["MountFSPrivileged"]),
        .executableTarget(name: "MountFSIdentity", dependencies: ["MountFSPrivileged"], path: "Sources/MountFSIdentity"),
        .executableTarget(name: "MountFSApp", dependencies: ["MountFSCore", "MountFSPrivileged"], path: "Sources/MountFSApp"),
        .testTarget(name: "MountFSCoreTests", dependencies: ["MountFSCore"])
    ]
)
