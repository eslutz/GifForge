// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "PromptGIFCore",
  platforms: [
    .iOS("26.5"),
    .macOS("15.0")
  ],
  products: [
    .library(
      name: "PromptGIFCore",
      targets: ["PromptGIFCore"]
    )
  ],
  targets: [
    .target(
      name: "PromptGIFCore"
    ),
    .testTarget(
      name: "PromptGIFCoreTests",
      dependencies: ["PromptGIFCore"]
    )
  ]
)
