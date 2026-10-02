// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HorseBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "slapd", targets: ["slapd"]),
        .executable(name: "HorseBar", targets: ["HorseBar"]),
    ],
    targets: [
        .target(name: "SlapCore"),
        .executableTarget(name: "slapd", dependencies: ["SlapCore"]),
        .executableTarget(name: "HorseBar", dependencies: ["SlapCore"]),
    ]
)
