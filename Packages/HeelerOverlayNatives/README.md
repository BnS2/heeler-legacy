# HeelerOverlayNatives (iOS 16)

Local copy of `heeler-overlay-natives` v1.0.3 with the package platform lowered to iOS 16.
The three static xcframeworks are not committed (large binaries). Recreate them:

1. Build the app once with the upstream dependency, or download the release zips from
   https://github.com/Ylarod/heeler-overlay-natives/releases/tag/v1.0.3
   (`CTailscale`, `CZeroTier`, `CEasyTier` `.xcframework.zip`).
2. Unzip the three `.xcframework` folders into this directory.

The binaries themselves still declare iOS 18 as their minimum; linking them into an iOS 16 app only warns.
Whether the overlay networks actually run on iOS 16 is untested.
