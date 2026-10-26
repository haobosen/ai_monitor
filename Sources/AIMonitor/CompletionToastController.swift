import AppKit
import SwiftUI

/// 屏幕顶部居中的任务完成提示条（自绘，不依赖系统通知权限）
final class CompletionToastController {

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var onOpen: () -> Void = {}

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

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            // 放在顶部正中，避免和右上角的小浮窗重叠
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 12
            ))
        }

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
