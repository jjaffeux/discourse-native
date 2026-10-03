// swift-tools-version: 5.9
import PackageDescription

// Exercise the actual encoder without requiring a Flutter engine or app host.
let package = Package(
  name: "VideoOptimization",
  platforms: [.macOS("12.0"), .iOS("15.0")],
  targets: [
    .target(
      name: "VideoOptimization",
      path: "darwin/discourse_video_optimizer/Sources/discourse_video_optimizer",
      exclude: ["VideoOptimizerPlugin.swift"],
      sources: ["VideoOptimizationJob.swift"]
    ),
    .testTarget(name: "VideoOptimizationTests", dependencies: ["VideoOptimization"], path: "Tests")
  ]
)
