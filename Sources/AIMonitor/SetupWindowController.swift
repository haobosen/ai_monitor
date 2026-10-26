import AppKit
import SwiftUI

/// 初始化 / 设置窗口
final class SetupWindowController: NSWindowController, NSWindowDelegate {

    private var isProgrammaticClose = false
    private var onUserClose: (() -> Void)?

    init(mode: SetupStore.Mode,
         onFinish: @escaping (Set<String>) -> Void,
         onSkip: @escaping () -> Void,
         onToggle: @escaping (String, Bool) -> Void,
         onUserClose: (() -> Void)? = nil) {
        self.onUserClose = onUserClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: mode == .onboarding ? [.titled] : [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI 任务监控"
        window.isMovableByWindowBackground = false
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 560)
        window.contentMaxSize = NSSize(width: 520, height: 560)

        let view = SetupView(mode: mode, onFinish: onFinish, onSkip: onSkip, onToggle: onToggle)
        window.contentView = NSHostingView(rootView: view)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        isProgrammaticClose = true
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard !isProgrammaticClose else { return }
        onUserClose?()
    }
}
