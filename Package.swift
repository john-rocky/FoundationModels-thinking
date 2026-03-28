// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepThinkKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "DeepThinkKit", targets: ["DeepThinkKit"]),
        .executable(name: "RunBenchmark", targets: ["RunBenchmark"])
    ],
    targets: [
        .target(
            name: "DeepThinkKit",
            path: "Sources/DeepThinkKit"
        ),
        .executableTarget(
            name: "RunBenchmark",
            dependencies: ["DeepThinkKit"],
            path: "Sources/RunBenchmark"
        ),
        .testTarget(
            name: "DeepThinkKitTests",
            dependencies: ["DeepThinkKit"],
            path: "Tests/DeepThinkKitTests"
        )
    ]
)
