// swift-tools-version: 6.0
import PackageDescription

// Platform-pure strap layer: framing, commands, history state, and the
// durable SQLite store. No SwiftUI and no CoreBluetooth in here; the app owns
// the Bluetooth edge (see docs/decisions.md, decision 2).
let package = Package(
    name: "AloftStrap",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AloftStrap", targets: ["AloftStrap"]),
    ],
    targets: [
        .target(
            name: "AloftStrap",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "AloftStrapTests", dependencies: ["AloftStrap"]),
    ]
)
