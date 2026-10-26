import AppKit
import SwiftUI

/// 主界面窗口：完整任务列表
final class MainWindowController: NSWindowController, NSWindowDelegate {

    private let store: TaskStore
    var onVisibilityChange: ((Bool) -> Void)?

    init(store: TaskStore, onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI 任务监控"
        window.minSize = NSSize(width: 560, height: 440)
        window.isReleasedWhenClosed = false
        // 固定浅色外观：和白色浮窗一致，避免深色模式下又变灰
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.contentView = NSHostingView(
            rootView: MainView(store: store, onRefresh: onRefresh, onSettings: onSettings)
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        // 主界面打开时切成常规应用，这样 Cmd+Tab 和 Dock 里都能找到它
        NSApp.setActivationPolicy(.regular)
        Log.write("主界面显示，激活策略 regular（Cmd+Tab 可见）")
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
        DispatchQueue.main.async {
            // 主界面关掉且没有其他普通窗口时，回到菜单栏应用
            let hasTitledWindow = NSApp.windows.contains {
                $0.isVisible && $0.canBecomeMain
            }
            if !hasTitledWindow {
                NSApp.setActivationPolicy(.accessory)
                Log.write("主界面关闭，激活策略 accessory")
            }
        }
    }
}
