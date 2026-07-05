import CoreGraphics
import ApplicationServices
import AppKit

/// 键盘拦截核心：CGEventTap 实现 4 大功能
///
/// 1. 屏蔽 Command+Q
/// 2. 交换左 Command/Option
/// 3. 交换右 Command/Option
/// 4. F1-F12 媒体键转标准功能键
///
/// 一个 event tap 同时监听：keyDown / keyUp / flagsChanged / NX_SYSDEFINED(14)
@MainActor
final class KeyboardInterceptor {
    private let state: AppState
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 合成事件标记魔数：合成事件在 eventSourceUserData 字段写入此值，
    /// callback 检查到则跳过处理，防止「合成→回调→再合成」死循环。
    private static let synthMagic: Int64 = 0x444F54414D414348 // "DOTAMACH" ASCII

    init(state: AppState) {
        self.state = state
    }

    // MARK: - 启停

    func start() {
        guard eventTap == nil else { return }
        guard state.hasAccessibilityPermission else {
            state.isInterceptorActive = false
            return
        }

        // 监听：keyDown(1<<9) + keyUp(1<<10) + flagsChanged(1<<12) + NX_SYSDEFINED(1<<14)
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << 14) // NX_SYSDEFINED，CGEventType 没有对应 case
        )

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,            // HID 层最早拦截点
            place: .headInsertEventTap,
            options: .defaultTap,           // 可拦截可修改
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: refcon
        ) else {
            state.isInterceptorActive = false
            return
        }

        self.eventTap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        state.isInterceptorActive = true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        state.isInterceptorActive = false
    }

    // MARK: - 事件处理入口（由全局 C 回调调用）

    /// 非 @MainActor：C 回调入口。event tap 注册在 main run loop，callback 在 main thread。
    /// 用 MainActor.assumeIsolated 进入 MainActor。
    nonisolated func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // event tap 被系统禁用：同步立即重启（避免 Task 延迟期间的拦截空窗）
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let tap = self.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    self.state.isInterceptorActive = CGEvent.tapIsEnabled(tap: tap)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        return MainActor.assumeIsolated {
            self.processEvent(type: type, event: event)
        }
    }

    @MainActor
    private func processEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 快速短路 0：合成事件放行（防回环）
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == Self.synthMagic {
            return Unmanaged.passUnretained(event)
        }

        // 快速短路 1：未启用拦截
        guard state.shouldIntercept else {
            return Unmanaged.passUnretained(event)
        }

        // NX_SYSDEFINED (媒体键) — type.rawValue == 14
        if type.rawValue == 14 {
            return handleMediaKey(event: event)
        }

        switch type {
        case .keyDown:
            // 屏蔽 Command+Q
            if state.blockCmdQ {
                let result = handleBlockCommandQ(event: event)
                if result == nil { return nil } // 已吞掉
            }
        case .flagsChanged:
            // 交换修饰键
            if state.swapLeftCmdOpt || state.swapRightCmdOpt {
                let result = handleSwapModifiers(event: event)
                if result == nil { return nil } // 原始事件已吞掉（已重发合成事件）
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - 功能 1：屏蔽 Command+Q

    /// keyCode 12 = Q 键。flags 用 contains 判断（flags 可能含其他 bit）。
    /// 只拦截 keyDown，keyUp 不用管（系统看 keyDown 触发菜单）。
    @MainActor
    private func handleBlockCommandQ(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if flags.contains(.maskCommand) && keyCode == 12 { // kVK_ANSI_Q = 0x0C = 12
            return nil // 吞掉，下游看不到
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - 功能 2&3：交换左/右 Command 和 Option

    /// 侧位修饰键 bit（IOKit/IOLLEvent.h，公开但不在 CGEventFlags Swift enum）
    private enum SideMask {
        static let leftCommand:  UInt64 = 0x08  // NX_DEVICELCMDKEYMASK  = 1 << 3
        static let rightCommand: UInt64 = 0x10  // NX_DEVICERCMDKEYMASK  = 1 << 4
        static let leftOption:   UInt64 = 0x20  // NX_DEVICELALTKEYMASK  = 1 << 5
        static let rightOption:  UInt64 = 0x40  // NX_DEVICERALTKEYMASK  = 1 << 6
    }

    /// 修饰键虚拟键码
    private enum ModKey {
        static let leftCommand:  CGKeyCode = 0x37 // 55
        static let rightCommand: CGKeyCode = 0x36 // 54
        static let leftOption:   CGKeyCode = 0x3A // 58
        static let rightOption:  CGKeyCode = 0x3D // 61
    }

    /// 处理 flagsChanged：根据开关决定是否重映射
    @MainActor
    private func handleSwapModifiers(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let rawFlags = event.flags.rawValue

        // 判断这个 flagsChanged 是按下还是抬起
        // 按下：对应侧位 bit 被设置；抬起：bit 被清除
        func isDown(_ key: CGKeyCode, side: UInt64) -> Bool {
            return keyCode == key && (rawFlags & side) != 0
        }
        func isUp(_ key: CGKeyCode, side: UInt64) -> Bool {
            return keyCode == key && (rawFlags & side) == 0
        }

        // 左侧交换
        if state.swapLeftCmdOpt {
            if isDown(ModKey.leftCommand, side: SideMask.leftCommand) {
                return synthAndSwap(from: ModKey.leftCommand,
                                    to: ModKey.leftOption,
                                    isDown: true,
                                    srcSide: SideMask.leftCommand,
                                    dstSide: SideMask.leftOption,
                                    originalEvent: event)
            }
            if isUp(ModKey.leftCommand, side: SideMask.leftCommand) {
                return synthAndSwap(from: ModKey.leftCommand,
                                    to: ModKey.leftOption,
                                    isDown: false,
                                    srcSide: SideMask.leftCommand,
                                    dstSide: SideMask.leftOption,
                                    originalEvent: event)
            }
            if isDown(ModKey.leftOption, side: SideMask.leftOption) {
                return synthAndSwap(from: ModKey.leftOption,
                                    to: ModKey.leftCommand,
                                    isDown: true,
                                    srcSide: SideMask.leftOption,
                                    dstSide: SideMask.leftCommand,
                                    originalEvent: event)
            }
            if isUp(ModKey.leftOption, side: SideMask.leftOption) {
                return synthAndSwap(from: ModKey.leftOption,
                                    to: ModKey.leftCommand,
                                    isDown: false,
                                    srcSide: SideMask.leftOption,
                                    dstSide: SideMask.leftCommand,
                                    originalEvent: event)
            }
        }

        // 右侧交换
        if state.swapRightCmdOpt {
            if isDown(ModKey.rightCommand, side: SideMask.rightCommand) {
                return synthAndSwap(from: ModKey.rightCommand,
                                    to: ModKey.rightOption,
                                    isDown: true,
                                    srcSide: SideMask.rightCommand,
                                    dstSide: SideMask.rightOption,
                                    originalEvent: event)
            }
            if isUp(ModKey.rightCommand, side: SideMask.rightCommand) {
                return synthAndSwap(from: ModKey.rightCommand,
                                    to: ModKey.rightOption,
                                    isDown: false,
                                    srcSide: SideMask.rightCommand,
                                    dstSide: SideMask.rightOption,
                                    originalEvent: event)
            }
            if isDown(ModKey.rightOption, side: SideMask.rightOption) {
                return synthAndSwap(from: ModKey.rightOption,
                                    to: ModKey.rightCommand,
                                    isDown: true,
                                    srcSide: SideMask.rightOption,
                                    dstSide: SideMask.rightCommand,
                                    originalEvent: event)
            }
            if isUp(ModKey.rightOption, side: SideMask.rightOption) {
                return synthAndSwap(from: ModKey.rightOption,
                                    to: ModKey.rightCommand,
                                    isDown: false,
                                    srcSide: SideMask.rightOption,
                                    dstSide: SideMask.rightCommand,
                                    originalEvent: event)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// 合成目标修饰键的 flagsChanged 事件，并吞掉原始事件
    @MainActor
    private func synthAndSwap(
        from srcKey: CGKeyCode,
        to dstKey: CGKeyCode,
        isDown: Bool,
        srcSide: UInt64,
        dstSide: UInt64,
        originalEvent: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let synth = CGEvent(
            keyboardEventSource: source,
            virtualKey: dstKey,
            keyDown: isDown
        ) else {
            return Unmanaged.passUnretained(originalEvent) // 合成失败，放行原始
        }

        // 标记合成事件，防回环
        synth.setIntegerValueField(.eventSourceUserData, value: Self.synthMagic)

        // 重建 flags：保留其他修饰键，清除源侧位 bit，设置目标侧位 bit
        var newRaw = originalEvent.flags.rawValue
        if isDown {
            newRaw &= ~srcSide      // 清源侧位
            newRaw |= dstSide       // 设目标侧位
        } else {
            newRaw &= ~srcSide      // 抬起时清源侧位
            newRaw &= ~dstSide      // 也清目标侧位
        }

        // 公开 flags（maskCommand / maskAlternate）也要相应调整
        let srcPublic = publicFlag(for: srcKey)
        let dstPublic = publicFlag(for: dstKey)
        newRaw &= ~srcPublic.rawValue
        if isDown {
            newRaw |= dstPublic.rawValue
        } else {
            // 抬起时也要清目标公开 flag，否则合成 keyUp 后目标修饰键状态残留
            newRaw &= ~dstPublic.rawValue
        }

        synth.flags = CGEventFlags(rawValue: newRaw)
        synth.post(tap: .cghidEventTap)

        return nil // 吞掉原始事件
    }

    private func publicFlag(for key: CGKeyCode) -> CGEventFlags {
        switch key {
        case ModKey.leftCommand, ModKey.rightCommand:
            return .maskCommand
        case ModKey.leftOption, ModKey.rightOption:
            return .maskAlternate
        default:
            return []
        }
    }

    // MARK: - 功能 4：F1-F12 媒体键转标准功能键

    /// NX_KEYTYPE 常量（IOKit/hidsystem/ev_keymap.h）
    private enum NXKey {
        static let soundUp:        Int32 = 0
        static let soundDown:      Int32 = 1
        static let brightnessUp:   Int32 = 2
        static let brightnessDown: Int32 = 3
        static let illuminationUp:   Int32 = 21
        static let illuminationDown: Int32 = 22
        static let mute:           Int32 = 7
        static let play:           Int32 = 16
        static let next:           Int32 = 17
        static let previous:       Int32 = 18
        // Mission Control / Launchpad 等
        static let missionControl: Int32 = 5
        static let launchpad:      Int32 = 6
    }

    /// 媒体键 keytype → F-key 虚拟键码（标准 MacBook 布局）
    private static let mediaToFKey: [Int32: CGKeyCode] = [
        NXKey.brightnessDown:   0x7A, // F1  (122)
        NXKey.brightnessUp:     0x78, // F2  (120)
        NXKey.missionControl:   0x63, // F3  (99)
        NXKey.launchpad:        0x76, // F4  (118)
        NXKey.illuminationDown: 0x60, // F5  (96)
        NXKey.illuminationUp:   0x61, // F6  (97)
        NXKey.previous:         0x62, // F7  (98)
        NXKey.play:             0x64, // F8  (100)
        NXKey.next:             0x65, // F9  (101)
        NXKey.mute:             0x6D, // F10 (109)
        NXKey.soundDown:        0x67, // F11 (103)
        NXKey.soundUp:           0x6F, // F12 (111)
    ]

    @MainActor
    private func handleMediaKey(event: CGEvent) -> Unmanaged<CGEvent>? {
        // 转为 NSEvent 解析 data1/data2（媒体键的 keytype 编码在 data1 高 16 位）
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        // subtype 8 = 媒体键通道
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyType = Int32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        let isRepeat = (keyFlags & 0x1) != 0

        // 只处理 keyDown 非 repeat；keyUp 直接吞掉（防止系统 HUD 弹出）
        if !isKeyDown {
            return nil
        }
        if isRepeat {
            return nil
        }

        guard let fKeyCode = Self.mediaToFKey[keyType] else {
            return Unmanaged.passUnretained(event) // 不在映射表，放行
        }

        // 合成 F-key 的 keyDown + keyUp
        let source = CGEventSource(stateID: .hidSystemState)

        if let fDown = CGEvent(keyboardEventSource: source, virtualKey: fKeyCode, keyDown: true) {
            fDown.setIntegerValueField(.eventSourceUserData, value: Self.synthMagic)
            // 保留修饰键状态（如 Shift+F1）
            fDown.flags = event.flags.intersection(CGEventFlags(rawValue: 0xFFFF0000))
            fDown.post(tap: .cghidEventTap)
        }
        if let fUp = CGEvent(keyboardEventSource: source, virtualKey: fKeyCode, keyDown: false) {
            fUp.setIntegerValueField(.eventSourceUserData, value: Self.synthMagic)
            fUp.flags = event.flags.intersection(CGEventFlags(rawValue: 0xFFFF0000))
            fUp.post(tap: .cghidEventTap)
        }

        return nil // 吞掉原始媒体键
    }
}

// MARK: - 全局 C 回调（不捕获 context，通过 refcon 拿到实例）

private func keyboardTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let interceptor = Unmanaged<KeyboardInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handleEvent(proxy: proxy, type: type, event: event)
}
