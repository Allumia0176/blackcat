// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BlackCat",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "BlackCat",
            path: "Sources/BlackCat",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
