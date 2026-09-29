// swift-tools-version: 5.9
import PackageDescription

// Uber's H3 C library (https://github.com/uber/h3), v4.5.0, unmodified apart from generating h3api.h from
// h3api.h.in, plus a small Swift wrapper. The same version the Psst server uses, so cell ids match.
let package = Package(
    name: "H3",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "H3", targets: ["H3"])],
    targets: [
        .target(name: "CH3", path: "Sources/CH3", cSettings: [.unsafeFlags(["-w"])]),
        .target(name: "H3", dependencies: ["CH3"], path: "Sources/H3"),
        .testTarget(name: "H3Tests", dependencies: ["H3"], path: "Tests/H3Tests"),
    ]
)
