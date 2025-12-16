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
            url: "https://github.com/Justmalhar/WhisperCppKit/releases/download/v0.1.1/WhisperCpp.xcframework.zip",
            checksum: "4e48e6efaf459bb5717705ade88f210d40845ef8867e42d8ffee0bfe26dace3d"
        ),

        .target(
            name: "WhisperCppKit",
            dependencies: ["WhisperCpp"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
            ]
        ),

        .executableTarget(
            name: "WhisperCppKitCLI",
            dependencies: ["WhisperCppKit"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
            ]
        ),

        .testTarget(
            name: "WhisperCppKitTests",
            dependencies: ["WhisperCppKit"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
            ]
        ),
    ]
)