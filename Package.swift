// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IpduoClockCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "IpduoClockCore", targets: ["IpduoClockCore"])
    ],
    targets: [
        .target(
            name: "IpduoClockCore",
            path: "Sources/IpduoClockCore"
        ),
        .testTarget(
            name: "IpduoClockCoreTests",
            dependencies: ["IpduoClockCore"],
            path: "Tests/IpduoClockCoreTests"
        )
    ]
)
