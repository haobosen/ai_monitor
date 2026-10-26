import AppKit
import SwiftUI

/// 屏幕顶部居中的任务完成提示条（自绘，不依赖系统通知权限）
final class CompletionToastController {

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var onOpen: () -> Void = {}
    /// 浮窗可见时返回其 frame，用于把提示条放到浮窗上方
    var panelFrameProvider: (() -> NSRect?)?
    /// 上一次提示条的位置：浮窗关闭后继续沿用
    private var lastOrigin: NSPoint?

    func show(task: AITask, muted: Bool, onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        dismiss(animated: false)

        let view = ToastView(
            task: task,
            onOpen: { [weak self] in
                self?.onOpen()
                self?.dismiss()
            },
            onClose: { [weak self] in self?.dismiss() }
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 340, height: 116)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.alphaValue = 0

        // NSHostingView 会按内容收缩，按实际尺寸定位
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        let size = NSSize(width: max(340, fitted.width), height: max(90, fitted.height))
        panel.setContentSize(size)

        position(panel, size: size)

        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        if !muted {
            NSSound(named: "Glass")?.play()
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    /// 有浮窗时贴在浮窗上方（放不下则放下方），浮窗关闭后沿用上一次的位置
    private func position(_ panel: NSPanel, size: NSSize) {
        guard let primary = NSScreen.main ?? NSScreen.screens.first else { return }
        let gap: CGFloat = 8
        var origin: NSPoint
        var screen = primary

        if let panelFrame = panelFrameProvider?() {
            screen = NSScreen.screens.first(where: { $0.frame.intersects(panelFrame) }) ?? primary
            let visible = screen.visibleFrame

            var y = panelFrame.maxY + gap
            if y + size.height > visible.maxY - 6 {
                // 屏幕顶部放不下时改到浮窗下方，避免被菜单栏挡住
                y = panelFrame.minY - size.height - gap
            }
            y = min(max(y, visible.minY + 6), visible.maxY - size.height - 6)

            var x = panelFrame.midX - size.width / 2
            x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
            origin = NSPoint(x: x, y: y)
        } else if let last = lastOrigin {
            screen = NSScreen.screens.first(where: { $0.frame.intersects(NSRect(origin: last, size: size)) }) ?? primary
            let visible = screen.visibleFrame
            origin = NSPoint(
                x: min(max(last.x, visible.minX + 6), visible.maxX - size.width - 6),
                y: min(max(last.y, visible.minY + 6), visible.maxY - size.height - 6)
            )
        } else {
            let visible = primary.visibleFrame
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 12
            )
        }

        lastOrigin = origin
        panel.setFrameOrigin(origin)
        Log.write("完成提示位置: panel=\(panelFrameProvider?().map(NSStringFromRect) ?? "nil") origin=\(NSStringFromRect(NSRect(origin: origin, size: size)))")
    }

    func dismiss(animated: Bool = true) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let panel else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
        }
        self.panel = nil
    }
}
