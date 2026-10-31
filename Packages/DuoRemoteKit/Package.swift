// swift-tools-version: 6.2
// Everything DuoRemote does, so it can run as its own app or inside another one.

import PackageDescription

// Same concurrency rules the app target builds with (SWIFT_APPROACHABLE_CONCURRENCY and
// SWIFT_DEFAULT_ACTOR_ISOLATION).
let concurrency: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "DuoRemoteKit",
    platforms: [.iOS("27.1")],
    products: [
        .library(name: "DuoRemoteKit", targets: ["DuoRemoteKit"])
    ],
    dependencies: [
        .package(path: "../../Vendor/RoyalVNCKit"),
        .package(path: "../../Vendor/TailscaleKit"),
    ],
    targets: [
        .target(
            name: "DuoRemoteKit",
            dependencies: ["RoyalVNCKit", "TailscaleKit"],
            resources: [.copy("App/Acknowledgements.txt")],
            swiftSettings: concurrency
        ),
        .testTarget(name: "DuoRemoteKitTests", dependencies: ["DuoRemoteKit"], swiftSettings: concurrency),
    ]
)
