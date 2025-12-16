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
            url: "https://github.com/Justmalhar/WhisperCppKit/releases/download/v0.1.0/WhisperCpp.xcframework.zip",
            checksum: "3eedf470200f811fe59e360638c30e0e6250569b9004d197d4e3019d3ea14bd8"
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