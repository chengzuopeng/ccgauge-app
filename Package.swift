// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CCGaugeBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CCGaugeBar", targets: ["CCGaugeBar"])
    ],
    targets: [
        .executableTarget(
            name: "CCGaugeBar",
            path: "Sources/CCGaugeBar",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
        ),
        .testTarget(
            name: "CCGaugeBarTests",
            dependencies: ["CCGaugeBar"],
            path: "Tests/CCGaugeBarTests"
        )
    ]
)
