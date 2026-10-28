// swift-tools-version:5.10
import PackageDescription

let package = Package(
  name: "BaristaAgent",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "barista-agent", path: "Sources/BaristaAgent"),
    .testTarget(name: "BaristaAgentTests", dependencies: ["barista-agent"], path: "Tests/BaristaAgentTests"),
  ]
)
