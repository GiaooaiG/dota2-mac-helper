import SwiftUI

/// 菜单栏弹窗主界面
struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if !state.hasAccessibilityPermission {
                        permissionCard
                    }
                    masterSection
                    featuresSection
                    scopeSection
                    statusSection
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 520)
        .background(.regularMaterial)
    }

    // MARK: - 顶部状态栏
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.statusBarSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dota Mac 助手")
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        if !state.hasAccessibilityPermission { return .orange }
        if !state.masterEnabled { return .secondary }
        if state.shouldIntercept { return .green }
        return .secondary
    }

    private var statusSubtitle: String {
        if !state.hasAccessibilityPermission { return "需要可访问性权限" }
        if !state.masterEnabled { return "已关闭" }
        if state.shouldIntercept { return "运行中 · \(state.scope.label)" }
        if state.scope == .dotaOnly && !state.isDota2Frontmost {
            return "待机 · 等待 Dota 2 启动"
        }
        return "待机"
    }

    // MARK: - 权限申请卡片
    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 6) {
                Text("需要可访问性权限")
                    .font(.subheadline.bold())
                Text("键盘拦截功能需要授权。点击下方按钮，在系统设置中允许 DotaMacHelper。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    AccessibilityPermission.openSystemSettings()
                } label: {
                    Label("打开系统设置", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 总开关
    private var masterSection: some View {
        @Bindable var state = state
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("总开关")
                    .font(.subheadline.bold())
                Text("关闭后所有拦截立即停止")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $state.masterEnabled)
                .toggleStyle(.switch)
                .controlSize(.large)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 功能开关
    private var featuresSection: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 0) {
            Text("功能开关")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 6)
                .padding(.horizontal, 4)

            featureRow(
                icon: "rectangle.slash",
                color: .red,
                title: "屏蔽 Command+Q/W",
                desc: "防止误触退出/关闭窗口",
                isOn: $state.blockCmdQ
            )
            Divider().padding(.vertical, 2)
            featureRow(
                icon: "arrow.left.arrow.right",
                color: .blue,
                title: "交换左 Command / Option",
                desc: "左侧 Win ↔ Alt 互换",
                isOn: $state.swapLeftCmdOpt
            )
            Divider().padding(.vertical, 2)
            featureRow(
                icon: "arrow.left.arrow.right",
                color: .blue,
                title: "交换右 Command / Option",
                desc: "右侧 Win ↔ Alt 互换",
                isOn: $state.swapRightCmdOpt
            )
            Divider().padding(.vertical, 2)
            featureRow(
                icon: "keyboard",
                color: .purple,
                title: "F1-F12 标准功能键",
                desc: "屏蔽媒体键，F1-F12 直接发送按键",
                isOn: $state.fkeysAsStandard
            )
        }
    }

    private func featureRow(
        icon: String,
        color: Color,
        title: String,
        desc: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: - 生效范围
    private var scopeSection: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 6) {
            Text("生效范围")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            Picker("", selection: $state.scope) {
                ForEach(ScopeMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - 状态信息
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("运行状态")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 2)
                .padding(.horizontal, 4)
            statusRow(label: "Dota 2 前台", value: state.isDota2Frontmost ? "是" : "否")
            statusRow(label: "拦截器", value: interceptorStatus)
            statusRow(label: "权限", value: state.hasAccessibilityPermission ? "已授权" : "未授权")
        }
    }


    private var interceptorStatus: String {
        if !state.hasAccessibilityPermission { return "未授权" }
        if !state.masterEnabled { return "已关闭" }
        if !state.isInterceptorActive { return "已停止" }
        if state.shouldIntercept { return "拦截中" }
        return "待机中"
    }
    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.monospaced())
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    // MARK: - 底部
    private var footer: some View {
        HStack {
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                // 可在此打开独立设置窗口（预留）
            } label: {
                Label("关于", systemImage: "info.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
