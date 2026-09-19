// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OrbitNotes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OrbitNotes",
            path: "Sources/OrbitNotes"
        )
    ]
)
