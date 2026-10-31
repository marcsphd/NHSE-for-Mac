// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ACNHSaveEditor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ACNHSaveEditor", targets: ["ACNHMac"])],
    targets: [
        .target(name: "SaveCrypto", publicHeadersPath: "include"),
        .target(name: "ACNHCore", dependencies: ["SaveCrypto"]),
        .executableTarget(name: "ACNHMac", dependencies: ["ACNHCore"], resources: [.process("Resources"), .copy("ExampleSave")]),
        .testTarget(name: "ACNHCoreTests", dependencies: ["ACNHCore", "SaveCrypto"]),
        .testTarget(name: "ACNHMacTests", dependencies: ["ACNHMac"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
