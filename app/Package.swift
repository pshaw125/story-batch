// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "StoryBatch",
    platforms: [.macOS(.v13)],
    products: [.library(name: "StoryBatchCore", targets: ["StoryBatchCore"]), .executable(name: "StoryBatch", targets: ["StoryBatchApp"])],
    targets: [
        .target(name: "StoryBatchCore"),
        .executableTarget(name: "StoryBatchApp", dependencies: ["StoryBatchCore"]),
        .testTarget(name: "StoryBatchCoreTests", dependencies: ["StoryBatchCore"])
    ]
)
