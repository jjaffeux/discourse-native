// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "discourse_voice",
  platforms: [
    .iOS("15.0")
  ],
  products: [
    .library(name: "discourse-voice", targets: ["discourse_voice"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "discourse_voice",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    ),
    .testTarget(
      name: "discourse_voiceTests",
      dependencies: ["discourse_voice"]
    ),
  ]
)
