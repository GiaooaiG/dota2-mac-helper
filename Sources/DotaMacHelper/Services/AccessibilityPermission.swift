@preconcurrency import ApplicationServices
import AppKit

/// 可访问性权限管理
///
/// CGEventTap 需要可访问性权限（Accessibility）。
/// macOS Sequoia (15) 起还可能需要「输入监控」权限，运行时按需引导。
enum AccessibilityPermission {

    /// 仅检查是否已授权（不弹框）
    static func check() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 请求权限：首次调用会弹系统对话框引导用户去「系统设置 > 隐私与安全 > 可访问性」
    @discardableResult
    static func request() -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 直接打开系统设置的「可访问性」面板
    static func openSystemSettings() {
        // macOS 13+ (Ventura/Tahoe) System Settings URL scheme
        // 兼容多种 URL 写法，按优先级尝试
        let urls: [URL] = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
            URL(string: "x-apple.systempreferences:com.apple.settings.preference.privacy?Privacy_Accessibility")!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security")!,
        ]
        for url in urls {
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
