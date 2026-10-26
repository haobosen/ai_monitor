import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 可拖动、置顶、常驻的监控浮窗
final class PanelController {

    private let panel: FloatingPanel
    private let store: TaskStore
    private let actions: PanelActions
    private var dragStartOrigin: NSPoint?
    private var hasRestoredFrame = false
    private let frameKey = "panelFrame"

    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool { panel.isVisible }

    init(store: TaskStore, onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.store = store
        self.actions = PanelActions()

        let contentSize = NSSize(
            width: Theme.panelWidth + Theme.outerMargin * 2,
            height: Theme.panelHeight + Theme.outerMargin * 2
        )
        let rect = NSRect(origin: .zero, size: contentSize)

        panel = FloatingPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.appearance = nil

        actions.refresh = onRefresh
        actions.openSettings = onSettings
        actions.hide = { [weak self] in self?.hide() }
        actions.dragBegan = { [weak self] in
            self?.dragStartOrigin = self?.panel.frame.origin
        }
        actions.dragChanged = { [weak self] translation in
            guard let self, let start = self.dragStartOrigin else { return }
            self.panel.setFrameOrigin(NSPoint(
                x: start.x + translation.width,
                y: start.y - translation.height
            ))
        }
        actions.dragEnded = { [weak self] in
            guard let self else { return }
            self.dragStartOrigin = nil
            self.clampToScreen()
            self.saveFrame()
        }

        let hosting = NSHostingView(rootView: RootView(store: store, actions: actions))
        hosting.frame = rect
        panel.contentView = hosting

        restoreFrame()
    }

    func show() {
        if !hasRestoredFrame { applyDefaultPosition() }
        panel.orderFrontRegardless()
        onVisibilityChange?(true)
    }

    func hide() {
        panel.orderOut(nil)
        onVisibilityChange?(false)
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    // MARK: - 位置

    private func applyDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 20,
            y: visible.maxY - size.height - 12
        )
        panel.setFrameOrigin(origin)
        hasRestoredFrame = true
    }

    private func restoreFrame() {
        guard let raw = UserDefaults.standard.string(forKey: frameKey) else { return }
        let stored = NSRectFromString(raw)
        guard stored.width > 100, stored.height > 100 else { return }

        // 尺寸以当前版本为准，只恢复位置；避免升级后窗口尺寸变化导致内容被裁切
        let frame = NSRect(origin: stored.origin, size: panel.frame.size)
        let intersects = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard intersects else { return }

        panel.setFrame(frame, display: false)
        hasRestoredFrame = true
    }

    /// 拖动结束后保证窗口至少有一部分留在屏幕内
    private func clampToScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        let size = panel.frame.size
        let minVisible: CGFloat = 80

        origin.x = min(origin.x, visible.maxX - minVisible)
        origin.x = max(origin.x, visible.minX - size.width + minVisible)
        origin.y = min(origin.y, visible.maxY - minVisible)
        origin.y = max(origin.y, visible.minY - size.height + minVisible)
        panel.setFrameOrigin(origin)
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }
}
