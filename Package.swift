// swift-tools-version: 6.2
import Foundation
import PackageDescription

// GlassDock・ShelfTabs・MissionView の機能を 1 つのアプリで使うための統合アプリ。
// 各機能は元のリポジトリのライブラリをそのまま読み込む（単体アプリと履歴はそれぞれのリポジトリに残す）。
// 隣に各リポジトリがあればそれを使い（開発時）、なければ公開済みのバージョンを GitHub から取得する
// 公開版のバージョンは scripts/update.sh が書き換える
let releases = [
    "GlassDock": "1.1.0",
    "ShelfTabs": "0.2.0",
    "MissionView": "0.1.0",
]

func feature(_ name: String) -> Package.Dependency {
    let local = Context.packageDirectory + "/../" + name
    if FileManager.default.fileExists(atPath: local + "/Package.swift") {
        return .package(path: local)
    }
    return .package(url: "https://github.com/Ryuto42/\(name).git", exact: Version(releases[name]!)!)
}

let package = Package(
    name: "Shoji",
    platforms: [.macOS(.v26)],
    dependencies: [
        feature("GlassDock"),
        feature("ShelfTabs"),
        feature("MissionView"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Shoji",
            dependencies: [
                .product(name: "GlassDockKit", package: "GlassDock"),
                .product(name: "ShelfTabsKit", package: "ShelfTabs"),
                .product(name: "MissionViewKit", package: "MissionView"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // .app に同梱した Sparkle.framework を見つけるため
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
