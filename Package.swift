// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "SwiftSlides",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SlideCore", targets: ["SlideCore"]),
        .library(name: "SlidePPTX", targets: ["SlidePPTX"]),
        .library(name: "SlideODP", targets: ["SlideODP"]),
        .library(name: "SwiftSlides", targets: ["SwiftSlides"]),
        .executable(name: "swiftslides", targets: ["SwiftSlidesCLI"])
    ],
    targets: [
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"]), .brew(["zlib"])]),
        .target(name: "SlideCore", dependencies: ["CZlib"]),
        .target(name: "SlidePPTX", dependencies: ["SlideCore"]),
        .target(name: "SlideODP", dependencies: ["SlideCore"]),
        .target(name: "SwiftSlides", dependencies: ["SlideCore", "SlidePPTX", "SlideODP"]),
        .executableTarget(name: "SwiftSlidesCLI", dependencies: ["SwiftSlides"]),
        .testTarget(name: "SwiftSlidesTests", dependencies: ["SwiftSlides"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PartialLinkTests", dependencies: ["SlideCore", "SlidePPTX", "SlideODP"])
    ],
    swiftLanguageModes: [.v6]
)
