// swift-tools-version: 6.0
// TailscaleKit (libtailscale), built by scripts/build-tailscalekit.sh. Not committed.

import PackageDescription

let package = Package(
    name: "TailscaleKit",
    platforms: [.iOS("27.1")],
    products: [
        .library(name: "TailscaleKit", targets: ["TailscaleKit"])
    ],
    targets: [
        .binaryTarget(name: "TailscaleKit", path: "TailscaleKit.xcframework")
    ]
)
