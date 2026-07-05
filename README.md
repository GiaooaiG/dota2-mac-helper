# Dota Mac 助手

为 Mac 玩 Dota 2 设计的键盘拦截工具，解决 macOS 上键位习惯冲突：

- **屏蔽 Command+Q/W** — 防止误触退出游戏/关闭窗口
- **交换左 Command / Option** — 左侧 Win ↔ Alt 互换（适配 PC 键盘习惯）
- **交换右 Command / Option** — 右侧 Win ↔ Alt 互换
- **F1-F12 标准功能键** — 屏蔽媒体键，F1-F12 直接发送按键
- **生效范围切换** — 仅 Dota 2 前台生效 / 全局生效

状态栏控件，不显示 Dock 图标。

---

## 环境要求

| 项 | 要求 |
|---|---|
| macOS | 14.0 (Sonoma) 及以上（推荐 26 Tahoe） |
| Xcode | 15.0 及以上（完整版，不是 Command Line Tools） |
| xcodegen | `brew install xcodegen` |
| 权限 | 可访问性（运行时引导授权） |

## 构建步骤

### 1. 安装依赖

```bash
# 从 App Store 安装完整 Xcode（约 12GB），然后：
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 安装 xcodegen
brew install xcodegen
```

### 2. 生成 Xcode 项目

```bash
cd <仓库根目录>
xcodegen generate
```

会生成 `DotaMacHelper.xcodeproj`。

### 3. 用 Xcode 打开并构建

```bash
open DotaMacHelper.xcodeproj
```

在 Xcode 里：
- 选 `DotaMacHelper` scheme
- `Cmd+R` 运行（或 `Cmd+B` 仅构建）

构建产物在 `build/DotaMacHelper.app`。

## 首次运行

1. 启动后状态栏出现手柄图标
2. 点击图标 → 弹窗提示需要可访问性权限
3. 点「打开系统设置」→ 系统设置 > 隐私与安全 > 可访问性
4. 找到 `DotaMacHelper`，打开开关
5. 回到助手，状态栏图标变绿（或黄），权限卡片消失
6. 打开总开关，开始使用

> macOS 15 (Sequoia) 起可能还会提示「输入监控」权限，同样在系统设置里授权。

## 使用

- **总开关**：一键启停所有拦截
- **4 个功能开关**：独立控制每个功能
- **生效范围**：
  - `仅 Dota 2 生效`：只在 Dota 2 在前台时拦截（默认）
  - `全局生效`：任何时候都拦截（会影响日常使用，谨慎开启）

## 项目结构

```
mac刀塔工具/
├── project.yml                          # xcodegen 配置
├── Sources/DotaMacHelper/
│   ├── App/
│   │   └── DotaMacHelperApp.swift       # @main 入口 + AppCoordinator + AppDelegate
│   ├── Models/
│   │   └── AppState.swift               # @Observable 全局状态 + 持久化
│   ├── Views/
│   │   └── ContentView.swift            # 菜单栏弹窗 UI
│   └── Services/
│       ├── KeyboardInterceptor.swift    # CGEventTap 核心键盘拦截
│       ├── FrontAppWatcher.swift        # 前台应用检测（Dota 2）
│       └── AccessibilityPermission.swift # 可访问性权限管理
└── Resources/
    ├── Info.plist                       # 由 xcodegen 生成
    ├── DotaMacHelper.entitlements       # 由 xcodegen 生成（非沙盒）
    └── Assets.xcassets/                 # 图标
```

## 技术说明

- **CGEventTap**：系统级键盘事件拦截，需要可访问性权限
- **非沙盒**：CGEventTap 不支持沙盒，故 entitlements 中 `app-sandbox: false`
- **Hardened Runtime**：开启，符合现代 macOS 应用要求
- **MenuBarExtra**：SwiftUI 原生状态栏组件（macOS 13+）
- **LSUIElement**：`YES`，应用不显示在 Dock，只在状态栏
- **持久化**：UserDefaults，JSON 编码快照

## 已知限制

- 交换 Command/Option 仅在按键事件层面生效，系统设置里的「修饰键」自定义可能覆盖
- F1-F12 媒体键转标准功能键是运行时拦截，不修改系统设置（即时不运行助手，系统设置行为不变）
- 触控板的 Force Touch 等不受影响
- 远程桌面（Screen Sharing）下 event tap 可能不生效

## 故障排查

**状态栏图标是橙色感叹号**
→ 可访问性权限未授权。打开系统设置 > 隐私与安全 > 可访问性，允许 DotaMacHelper。

**打开了开关但按键没变化**
→ 检查「生效范围」。如果设为「仅 Dota 2 生效」，需先启动 Dota 2 并切到前台。

**event tap 被系统禁用**
→ 长时间无响应时系统可能禁用 event tap，代码会自动重启。如果仍无效，重启助手。

**Dota 2 检测不到**
→ 确认是通过 Steam 启动的 Dota 2（bundle id: `com.valvesoftware.dota2`）。如果用了非标准启动方式，可能需要手动匹配进程名。

## License

MIT
