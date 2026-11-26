// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HeadProbe",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // xtool builds the app from this library product.
        .library(
            name: "HeadProbe",
            targets: ["HeadProbe"]
        ),
    ],
    targets: [
        .target(
            name: "HeadProbe"
        ),
    ],
    // Swift 5 mode: the audio and motion callbacks run on our own serial queue, and the strict
    // Swift 6 concurrency checks would reject that pattern without adding any safety here.
    swiftLanguageModes: [.v5]
)
