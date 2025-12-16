// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperCppKit",
    platforms: [
        .iOS(.v14),
        .macOS(.v13)
    ],
    products: [
        .library(name: "WhisperCppKit", targets: ["WhisperCppKit"]),
        .library(name: "WhisperCpp", targets: ["WhisperCpp"]),
        .executable(name: "whispercppkit-cli", targets: ["WhisperCppKitCLI"]),
    ],
    targets: [
        .binaryTarget(
            name: "WhisperCpp",
            path: "Frameworks/WhisperCpp.xcframework"
        ),

        .target(
            name: "WhisperCppKit",
            dependencies: ["WhisperCpp"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),

        .executableTarget(
            name: "WhisperCppKitCLI",
            dependencies: ["WhisperCppKit"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),

        .testTarget(
            name: "WhisperCppKitTests",
            dependencies: ["WhisperCppKit"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)