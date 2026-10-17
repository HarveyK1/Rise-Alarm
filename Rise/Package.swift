// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rise",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // xtool.yml says which product is the app and which is the widget extension.
        .library(
            name: "Rise",
            targets: ["Rise"]
        ),
        .library(
            name: "RiseWidget",
            targets: ["RiseWidget"]
        ),
    ],
    targets: [
        .target(
            name: "Rise",
            dependencies: ["RiseShared"]
        ),
        .target(
            name: "RiseWidget",
            dependencies: ["RiseShared"],
            // xtool links extensions from an empty stub with entry _NSExtensionMain, so nothing pulls in
            // this target's code and the widget ships empty. Force its @main (and everything it uses) in.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]
        ),
        // The Live Activity's data type, used by both the app and the widget.
        .target(
            name: "RiseShared"
        ),
    ],
    swiftLanguageModes: [.v5]
)
