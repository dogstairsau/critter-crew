// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CritterCrew",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CritterCrew", path: "Sources/CritterCrew")
    ]
)
