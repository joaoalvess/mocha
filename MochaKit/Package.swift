// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MochaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MochaProtocol", targets: ["MochaProtocol"]),
        .library(name: "MochaClient", targets: ["MochaClient"]),
        .library(name: "MochaDemo", targets: ["MochaDemo"]),
        .executable(name: "mochad", targets: ["mochad"]),
    ],
    targets: [
        .target(name: "MochaProtocol"),
        .target(name: "MochaClient", dependencies: ["MochaProtocol"]),
        .target(name: "MochaDemo", dependencies: ["MochaProtocol"]),
        .target(name: "MochaTranscript", dependencies: ["MochaProtocol"]),
        .target(name: "MochaHerdr"),
        .target(name: "MochaDaemonCore", dependencies: ["MochaProtocol", "MochaTranscript", "MochaHerdr"]),
        .executableTarget(name: "mochad", dependencies: ["MochaDaemonCore"]),
        .target(name: "MochaTestSupport", dependencies: ["MochaProtocol", "MochaDaemonCore"]),
        .testTarget(name: "MochaProtocolTests", dependencies: ["MochaProtocol"]),
        .testTarget(name: "MochaDemoTests", dependencies: ["MochaDemo", "MochaProtocol"]),
        .testTarget(name: "MochaClientTests", dependencies: ["MochaClient", "MochaDaemonCore"]),
        .testTarget(name: "MochaTranscriptTests", dependencies: ["MochaTranscript"]),
        .testTarget(name: "MochaHerdrTests", dependencies: ["MochaHerdr"]),
        .testTarget(name: "MochaDaemonCoreTests", dependencies: ["MochaDaemonCore", "MochaTestSupport"]),
    ]
)
