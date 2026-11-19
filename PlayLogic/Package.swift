// swift-tools-version: 5.9
import PackageDescription

/**
 * PlayLogic: two-button navigation with per-track resume, as described in LOGIC_FOR_PLAY.md.
 *
 * One copy of this package is shared by:
 *   - logic_for_play_demo (macOS demo app)
 *   - sanemp3 (iOS app)
 * Both add it as a local package dependency by relative path. Never copy the sources.
 */
let package = Package(
    name: "PlayLogic",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PlayLogic", targets: ["PlayLogic"]),
    ],
    targets: [
        .target(name: "PlayLogic"),
        .testTarget(name: "PlayLogicTests", dependencies: ["PlayLogic"]),
    ]
)
