// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Stillpin", platforms: [.macOS(.v13)],
  products: [.executable(name: "Stillpin", targets: ["Stillpin"])],
  targets: [
    .executableTarget(name: "Stillpin"),
    .testTarget(name: "StillpinTests", dependencies: ["Stillpin"]),
  ])
