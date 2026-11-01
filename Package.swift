// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeekdownNativeSupport",
    platforms: [.macOS(.v12)],
    products: [.library(name: "PeekdownNativeSupport", type: .static, targets: ["PeekdownNativeSupport"])],
    dependencies: [
        .package(path: "Vendor/SwiftMath"),
        .package(url: "https://github.com/lukilabs/beautiful-mermaid-swift", revision: "6a23a29e91af8f5b3e9fc09945332ca193bd69ec")
    ],
    targets: [.target(name: "PeekdownNativeSupport", dependencies: [
        .product(name: "SwiftMath", package: "SwiftMath"),
        .product(name: "BeautifulMermaid", package: "beautiful-mermaid-swift")
    ], path: "NativeSupport")]
)
