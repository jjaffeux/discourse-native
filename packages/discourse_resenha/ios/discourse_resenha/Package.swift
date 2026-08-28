// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "discourse_resenha",
  platforms: [
    .iOS("15.0")
  ],
  products: [
    .library(name: "discourse-resenha", targets: ["discourse_resenha"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "discourse_resenha",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    ),
    .testTarget(
      name: "discourse_resenhaTests",
      dependencies: ["discourse_resenha"]
    ),
  ]
)
