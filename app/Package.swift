// swift-tools-version:5.10
import PackageDescription

// WinSteam：bin/winsteam 的原生 macOS 圖形介面。
// 只支援 Apple Silicon（arm64）與 macOS 14 以上，不使用任何第三方套件。
let package = Package(
    name: "WinSteam",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WinSteam", targets: ["WinSteam"])
    ],
    targets: [
        .executableTarget(
            name: "WinSteam",
            path: "Sources/WinSteam"
        )
    ]
)
