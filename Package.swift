// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AptevaNativeSDK",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "AptevaNativeSDK", targets: ["AptevaNativeSDK"]),
        .library(name: "AptevaNativeUIKit", targets: ["AptevaNativeUIKit"]),
    ],
    targets: [
        .target(
            name: "AptevaNativeSDK",
            path: "apple/Sources",
            exclude: ["Assets"]
        ),
        .target(
            name: "AptevaNativeUIKit",
            dependencies: ["AptevaNativeSDK"],
            path: "apple/Sources/Assets"
        ),
        .testTarget(
            name: "AptevaNativeSDKTests",
            dependencies: ["AptevaNativeSDK", "AptevaNativeUIKit"],
            path: "apple/Tests"
        ),
    ]
)
