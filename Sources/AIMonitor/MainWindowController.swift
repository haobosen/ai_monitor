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
        window.titlebarAppearsTransparent = false
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
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }
}
