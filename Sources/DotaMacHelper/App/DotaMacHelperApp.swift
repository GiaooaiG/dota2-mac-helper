import SwiftUI

@main
struct DotaMacHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appDelegate.coordinator.state)
        } label: {
            Image(systemName: appDelegate.coordinator.state.statusBarSymbol)
                .help(appDelegate.coordinator.state.statusBarTooltip)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 应用协调器：持有全局状态 + 启动各 Service
@MainActor
final class AppCoordinator {
    let state: AppState
    private var keyboardInterceptor: KeyboardInterceptor?
    private var frontAppWatcher: FrontAppWatcher?
    private var permissionTimer: Timer?

    init() {
        self.state = AppState()
    }

    private var hasRequestedPermission = false

    func start() {
        // 1. 权限检查（首次）
        refreshPermission()

        // 2. 启动前台应用检测
        let watcher = FrontAppWatcher(state: state)
        watcher.start()
        self.frontAppWatcher = watcher

        // 3. 启动键盘拦截
        let interceptor = KeyboardInterceptor(state: state)
        interceptor.start()
        self.keyboardInterceptor = interceptor

        // 4. 定期复查权限（用户可能在系统设置里刚授权）
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermission()
            }
        }
    }

    func refreshPermission() {
        let oldGranted = state.hasAccessibilityPermission
        if hasRequestedPermission {
            // 后续检查：不弹框
            state.hasAccessibilityPermission = AccessibilityPermission.check()
        } else {
            // 首次：弹系统对话框引导授权
            hasRequestedPermission = true
            state.hasAccessibilityPermission = AccessibilityPermission.request()
        }
        if !state.permissionChecked {
            state.permissionChecked = true
        }

        // 权限状态变化时同步拦截器
        let newGranted = state.hasAccessibilityPermission
        if newGranted != oldGranted {
            if newGranted {
                // 权限刚获得：尝试启动拦截器（之前可能 start 失败）
                keyboardInterceptor?.start()
            } else {
                // 权限丢失：停止拦截器
                keyboardInterceptor?.stop()
            }
        }
    }
}

/// AppDelegate：在 applicationDidFinishLaunching 启动协调器
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}
