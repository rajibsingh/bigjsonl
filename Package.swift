// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "bigjsonl",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "bigjsonl", targets: ["bigjsonl-cli"]),
        .executable(name: "BigJSONLApp", targets: ["BigJSONLApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/rarestype/swift-json", from: "1.0.0")
    ],
    targets: [
        // Shared core library — zero Foundation JSON dependency, uses swift-json
        .target(
            name: "BigJSONLCore",
            dependencies: [
                .product(name: "JSON", package: "swift-json")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),

        // CLI tool
        .executableTarget(
            name: "bigjsonl-cli",
            dependencies: [
                "BigJSONLCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),

        // SwiftUI app (macOS 15+)
        .executableTarget(
            name: "BigJSONLApp",
            dependencies: ["BigJSONLCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),

        // Tests
        .testTarget(
            name: "BigJSONLCoreTests",
            dependencies: ["BigJSONLCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),

        // App tests — uncomment when adding SwiftUI-specific tests
        // .testTarget(
        //     name: "BigJSONLAppTests",
        //     dependencies: ["BigJSONLApp"],
        //     swiftSettings: [
        //         .enableUpcomingFeature("StrictConcurrency"),
        //         .swiftLanguageMode(.v6)
        //     ]
        // )
    ]
)
