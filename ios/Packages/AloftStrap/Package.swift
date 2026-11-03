// swift-tools-version: 6.0
import PackageDescription

// Platform-pure strap layer: framing, commands, history state, and the
// durable SQLite store. No SwiftUI and no CoreBluetooth in here; the app owns
// the Bluetooth edge (see docs/decisions.md, decision 2).
//
// Apple ships a SQLite3 module. Linux does not, so this manifest adds a
// system-library shim around the installed libsqlite3 when the host is Linux.
#if os(Linux)
let sqlite: [Target.Dependency] = ["CSQLite"]
let extraTargets: [Target] = [.systemLibrary(name: "CSQLite", path: "Sources/CSQLite")]
#else
let sqlite: [Target.Dependency] = []
let extraTargets: [Target] = []
#endif

let package = Package(
    name: "AloftStrap",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AloftStrap", targets: ["AloftStrap"]),
    ],
    targets: extraTargets + [
        .target(
            name: "AloftStrap",
            dependencies: sqlite,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "AloftStrapTests", dependencies: ["AloftStrap"]),
    ]
)
