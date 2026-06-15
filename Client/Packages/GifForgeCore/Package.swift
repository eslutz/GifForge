// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "GifForgeCore",
  platforms: [
    .iOS("26.5"),
    .macOS("15.0")
  ],
  products: [
    .library(
      name: "GifForgeCore",
      targets: ["GifForgeCore"]
    )
  ],
  targets: [
    .target(
      name: "GifForgeCore"
    ),
    .testTarget(
      name: "GifForgeCoreTests",
      dependencies: ["GifForgeCore"]
    )
  ]
)
