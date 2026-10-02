// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SpaceShareKit", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "SpaceShareKit", targets: ["SpaceShareKit"])], targets: [.target(name: "SpaceShareKit"), .testTarget(name: "SpaceShareKitTests", dependencies: ["SpaceShareKit"])])
