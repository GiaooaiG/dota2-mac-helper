import Foundation
import SwiftUI

/// 拦截生效范围
enum ScopeMode: String, CaseIterable, Codable {
    case global
    case dotaOnly

    var label: String {
        switch self {
        case .global: return "全局生效"
        case .dotaOnly: return "仅 Dota 2 生效"
        }
    }
}

/// 全局应用状态：持久化开关 + 运行时状态 + 业务计算属性
///
/// 所有可变属性通过 `didSet` 自动持久化到 `UserDefaults`。
/// 标记 `@MainActor` 因为 CGEventTap 回调在 main run loop 触发，
/// 且 SwiftUI UI 也运行在 main actor。
@MainActor
@Observable
final class AppState {
    // MARK: - 持久化设置（didSet 自动保存）

    /// 总开关
    var masterEnabled: Bool {
        didSet { save() }
    }
    /// 屏蔽 Command+Q
    var blockCmdQ: Bool {
        didSet { save() }
    }
    /// 交换左 Command / Option
    var swapLeftCmdOpt: Bool {
        didSet { save() }
    }
    /// 交换右 Command / Option
    var swapRightCmdOpt: Bool {
        didSet { save() }
    }
    /// F1-F12 回归标准功能键
    var fkeysAsStandard: Bool {
        didSet { save() }
    }
    /// 生效范围
    var scope: ScopeMode {
        didSet { save() }
    }

    // MARK: - 运行时状态（不持久化）

    /// 是否已获得可访问性权限
    var hasAccessibilityPermission: Bool = false
    /// Dota 2 是否在前台
    var isDota2Frontmost: Bool = false
    /// event tap 是否真的在运行（系统可能禁用）
    var isInterceptorActive: Bool = false
    /// 权限检查是否已完成（首次启动用）
    var permissionChecked: Bool = false

    // MARK: - 计算属性

    /// 当前是否应该拦截键盘（综合判断）
    var shouldIntercept: Bool {
        guard masterEnabled, hasAccessibilityPermission else { return false }
        switch scope {
        case .global: return true
        case .dotaOnly: return isDota2Frontmost
        }
    }

    /// 状态栏图标 tooltip
    var statusBarTooltip: String {
        if !masterEnabled { return "Dota Mac 助手 — 已关闭" }
        if !hasAccessibilityPermission { return "Dota Mac 助手 — 需要可访问性权限" }
        if shouldIntercept {
            return "Dota Mac 助手 — 运行中（\(scope.label)）"
        }
        return "Dota Mac 助手 — 待机（\(scope.label)）"
    }

    /// 状态栏 SF Symbol
    var statusBarSymbol: String {
        if !hasAccessibilityPermission { return "exclamationmark.shield" }
        if !masterEnabled { return "gamecontroller" }
        if shouldIntercept { return "gamecontroller.fill" }
        return "gamecontroller"
    }

    // MARK: - 持久化

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.dotamac.helper.settings.v1"

    /// 持久化的设置快照（只包含需要序列化的字段）
    private struct Snapshot: Codable {
        var masterEnabled: Bool
        var blockCmdQ: Bool
        var swapLeftCmdOpt: Bool
        var swapRightCmdOpt: Bool
        var fkeysAsStandard: Bool
        var scope: ScopeMode
    }

    init() {
        // 默认值（首次启动）
        let defaults = Snapshot(
            masterEnabled: false,
            blockCmdQ: true,
            swapLeftCmdOpt: true,
            swapRightCmdOpt: true,
            fkeysAsStandard: true,
            scope: .dotaOnly
        )

        // 从 UserDefaults 加载
        if let data = UserDefaults.standard.data(forKey: "com.dotamac.helper.settings.v1"),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.masterEnabled = snap.masterEnabled
            self.blockCmdQ = snap.blockCmdQ
            self.swapLeftCmdOpt = snap.swapLeftCmdOpt
            self.swapRightCmdOpt = snap.swapRightCmdOpt
            self.fkeysAsStandard = snap.fkeysAsStandard
            self.scope = snap.scope
        } else {
            self.masterEnabled = defaults.masterEnabled
            self.blockCmdQ = defaults.blockCmdQ
            self.swapLeftCmdOpt = defaults.swapLeftCmdOpt
            self.swapRightCmdOpt = defaults.swapRightCmdOpt
            self.fkeysAsStandard = defaults.fkeysAsStandard
            self.scope = defaults.scope
        }
    }

    private func save() {
        let snap = Snapshot(
            masterEnabled: masterEnabled,
            blockCmdQ: blockCmdQ,
            swapLeftCmdOpt: swapLeftCmdOpt,
            swapRightCmdOpt: swapRightCmdOpt,
            fkeysAsStandard: fkeysAsStandard,
            scope: scope
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    // MARK: - 业务方法

    /// 一键开启所有功能
    func enableAll() {
        blockCmdQ = true
        swapLeftCmdOpt = true
        swapRightCmdOpt = true
        fkeysAsStandard = true
    }

    /// 一键关闭所有功能（保留总开关状态）
    func disableAllFeatures() {
        blockCmdQ = false
        swapLeftCmdOpt = false
        swapRightCmdOpt = false
        fkeysAsStandard = false
    }
}
