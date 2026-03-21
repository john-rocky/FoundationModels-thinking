// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepThinkKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "DeepThinkKit", targets: ["DeepThinkKit"])
    ],
    targets: [
        .target(
            name: "DeepThinkKit",
            path: "Sources/DeepThinkKit"
        ),
        .testTarget(
            name: "DeepThinkKitTests",
            dependencies: ["DeepThinkKit"],
            path: "Tests/DeepThinkKitTests"
        )
    ]
)
