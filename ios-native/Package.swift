// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PVECenter",
    defaultLocalization: "fr",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .executable(name: "PVECenter", targets: ["PVECenter"]),
    ],
    targets: [
        .executableTarget(
            name: "PVECenter",
            path: "PVECenter",
            exclude: ["Resources"]
        ),
    ]
)
