//
//  AXCast.swift
//  HuaciGongju
//
//  跨进程 AX 取值的类型安全转换。

import Foundation
import ApplicationServices

/// 把 `AXUIElementCopyAttributeValue` 返回的 `CFTypeRef?` 转成具体 AX 类型。
///
/// ## 为什么不能写 `as?`
/// Swift 编译器**拒绝**对 CoreFoundation 类型做可失败转换：
///
/// ```
/// error: conditional downcast to CoreFoundation type 'AXUIElement' will always succeed
/// note: did you mean to explicitly compare the CFTypeIDs of 'parentVal' and 'AXUIElement'?
/// ```
///
/// 于是历史代码里清一色是 `as!`。但跨进程 AX 的返回值并不老实：Electron / Java /
/// 游戏 / 自绘 GUI 在权限半授权、或属性名被它们自行接管时，会返回 NSNull、NSNumber
/// 甚至完全不相干的 CF 对象。强转的代价是**整个划词 / 分屏链路崩溃**，
/// 而类型不符本来只该等于「这次取不到，走降级路径」。
///
/// 正确做法是编译器建议的那条：先比 CFTypeID，再强转。本文件把这两步封在一起，
/// 让调用方拿到的是 `AXUIElement?` / `AXValue?`，类型不符就得到 nil。
internal enum AXCast {
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // 上一行的类型 ID 已经比对过，此处强转必然成功
        return (value as! AXUIElement)
    }

    static func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
