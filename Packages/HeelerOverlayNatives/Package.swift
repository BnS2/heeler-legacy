// swift-tools-version: 6.0
// iOS 16: prebuilt iOS 18 natives re-labelled to minos 16 (may crash on missing symbols)
import PackageDescription
let package = Package(
    name: "heeler-overlay-natives",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "CTailscale", targets: ["CTailscale"]),
        .library(name: "CZeroTier", targets: ["CZeroTier"]),
        .library(name: "CEasyTier", targets: ["CEasyTier"]),
    ],
    targets: [
        .binaryTarget(name: "CTailscale", path: "CTailscale.xcframework"),
        .binaryTarget(name: "CZeroTier", path: "CZeroTier.xcframework"),
        .binaryTarget(name: "CEasyTier", path: "CEasyTier.xcframework"),
    ]
)
