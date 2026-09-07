// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "DiscourseNativeSupport",
  platforms: [.macOS(.v11), .iOS(.v13)],
  targets: [
    .target(
      name: "DiscourseNativeSupport",
      path: ".",
      exclude: ["Tests"],
      sources: ["PushRegistrationCoordinator.swift"]
    ),
    .testTarget(
      name: "DiscourseNativeSupportTests",
      dependencies: ["DiscourseNativeSupport"],
      path: "Tests"
    ),
  ]
)
