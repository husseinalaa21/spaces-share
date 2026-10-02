// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SpacesShareKit", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "SpacesShareKit", targets: ["SpacesShareKit"])], targets: [.target(name: "SpacesShareKit"), .testTarget(name: "SpacesShareKitTests", dependencies: ["SpacesShareKit"])])
