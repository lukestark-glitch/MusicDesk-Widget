// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MusicDesk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MusicDesk", targets: ["MusicDesk"])
    ],
    targets: [
        .executableTarget(
            name: "MusicDesk",
            path: "Sources/MusicDesk"
        )
    ]
)
