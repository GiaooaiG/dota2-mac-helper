import AppKit

/// 监听前台应用变化，判断 Dota 2 是否在前台
///
/// Dota 2 的 bundle id 为 `com.valvesoftware.dota2`。
/// 同时用进程名兜底（Steam 启动的游戏偶尔 bundle id 不可用）。
@MainActor
final class FrontAppWatcher {
    private let state: AppState
    private var observer: NSObjectProtocol?

    /// Dota 2 的 bundle id 集合
    private static let dotaBundleIds: Set<String> = [
        "com.valvesoftware.dota2",
    ]
    /// Dota 2 的进程名兜底匹配
    private static let dotaProcessKeywords: Set<String> = [
        "dota2",
    ]

    init(state: AppState) {
        self.state = state
    }

    func start() {
        // 初始检测
        update()

        // 监听前台应用切换
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func update() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let isDota = isDota2(frontApp)
        if isDota != state.isDota2Frontmost {
            state.isDota2Frontmost = isDota
        }
    }

    private func isDota2(_ app: NSRunningApplication?) -> Bool {
        guard let app = app else { return false }
        // 优先用 bundle id
        if let bid = app.bundleIdentifier, Self.dotaBundleIds.contains(bid) {
            return true
        }
        // 兜底：进程名或 executableURL
        if let name = app.localizedName?.lowercased(),
           Self.dotaProcessKeywords.contains(where: { name.contains($0) }) {
            return true
        }
        if let execURL = app.executableURL,
           let last = execURL.lastPathComponent.lowercased() as String?,
           Self.dotaProcessKeywords.contains(where: { last.contains($0) }) {
            return true
        }
        return false
    }
}
