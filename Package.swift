// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchBible",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchBible", targets: ["NotchBible"])],
    targets: [
        .target(name: "BibleCore", resources: [.process("Resources")]),
        .executableTarget(name: "NotchBible", dependencies: ["BibleCore"]),
        .testTarget(name: "BibleCoreTests", dependencies: ["BibleCore"]),
        .testTarget(name: "NotchBibleTests", dependencies: ["NotchBible", "BibleCore"])
    ]
)
