// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PVECenter",
    defaultLocalization: "fr",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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
