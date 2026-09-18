// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OurGroceriesApp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GroceriesCore", targets: ["GroceriesCore"]),
        .executable(name: "og-dev", targets: ["og-dev"])
    ],
    targets: [
        .target(name: "GroceriesCore"),
        .executableTarget(name: "og-dev", dependencies: ["GroceriesCore"]),
        .testTarget(name: "GroceriesCoreTests", dependencies: ["GroceriesCore"])
    ]
)
