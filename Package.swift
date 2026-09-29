// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "RemoveMacAI",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "removemacai", targets: ["removemacai"])],
  targets: [
    .target(name: "UAF", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
    .executableTarget(name: "removemacai", dependencies: ["UAF"]),
  ]
)
