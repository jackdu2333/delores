// swift-tools-version: 5.9
import PackageDescription

// 结构说明：
//   HuaciGongjuKit   —— 全部核心逻辑（UI / 服务 / 配置），可被测试 target 导入
//   HuaciGongju      —— 仅可执行入口 main.swift，依赖 Kit
//   HuaciGongjuTests —— 测试可执行程序，由 build.sh 显式运行
//
// 关于测试形态：本机仅安装 Command Line Tools、未装 Xcode，
// XCTest.framework 不可用（swift test 会报 `unable to resolve module dependency: 'XCTest'`），
// 故测试做成独立 executable target —— 不依赖任何测试框架，保证「构建即跑测试」。
let package = Package(
    name: "HuaciGongju",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HuaciGongju", targets: ["HuaciGongju"]),
        .library(name: "HuaciGongjuKit", targets: ["HuaciGongjuKit"])
    ],
    targets: [
        .target(
            name: "HuaciGongjuKit",
            path: "Sources/HuaciGongju",
            // 允许测试访问 internal 成员；仅 debug 生效，release 产品不受影响
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "HuaciGongju",
            dependencies: ["HuaciGongjuKit"],
            path: "Sources/HuaciGongjuMain"
        ),
        .executableTarget(
            name: "HuaciGongjuTests",
            dependencies: ["HuaciGongjuKit"],
            path: "Tests/HuaciGongjuTests"
        )
    ]
)
