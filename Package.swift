// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Maybe",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Maybe", targets: ["Maybe"]),
        .executable(name: "maybe", targets: ["MaybeCLI"])
    ],
    targets: [
        .target(name: "Maybe"),
        .executableTarget(name: "MaybeCLI", dependencies: ["Maybe"]),
        .testTarget(name: "MaybeTests", dependencies: ["Maybe"], resources: [.copy("Fixtures")])
    ]
)
