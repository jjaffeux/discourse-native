// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "discourse_video_optimizer",
  platforms: [.iOS("15.0"), .macOS("12.0")],
  products: [.library(name: "discourse-video-optimizer", targets: ["discourse_video_optimizer"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [
    .target(
      name: "discourse_video_optimizer",
      dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
    )
  ]
)
