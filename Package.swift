// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "agm",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "agm", targets: ["agm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.26.0"),
    ],
    targets: [
        .executableTarget(
            name: "agm",
            dependencies: [
                .product(name: "FlyingFox", package: "FlyingFox"),
            ],
            path: "Sources/agm"
        ),
    ]
)
