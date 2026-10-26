import AppKit
import SwiftUI
import Combine

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 小型浮窗：只列出 AI，点击打开主界面
final class PanelController {

    private let panel: FloatingPanel
    private let store: TaskStore
    private let actions: PanelActions

    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var hasRestoredFrame = false
    private var cancellables = Set<AnyCancellable>()
    private var dragObserver: NSObjectProtocol?
    private let frameKey = "panelFrame"

    var onVisibilityChange: ((Bool) -> Void)?
    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    init(store: TaskStore, onOpenMain: @escaping (String?) -> Void) {
        self.store = store
        self.actions = PanelActions()

        let initialRows = CompactRows.models(
            tasks: store.tasks,
            enabled: AppConfig.shared.enabledProviders
        ).count
        let size = CompactLayout.panelSize(rows: initialRows)

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.acceptsMouseMovedEvents = true

        actions.openMain = onOpenMain
        actions.hide = { [weak self] in self?.hide() }
        actions.dragBegan = { [weak self] in
            guard let self else { return }
            self.dragStartOrigin = self.panel.frame.origin
            self.dragStartMouse = NSEvent.mouseLocation
        }
        actions.dragChanged = { [weak self] _ in
            // 用屏幕坐标计算位移：SwiftUI 的 translation 会随窗口移动而变化，
            // 直接使用会导致窗口跟不上鼠标。
            guard let self,
                  let origin = self.dragStartOrigin,
                  let startMouse = self.dragStartMouse else { return }
            let current = NSEvent.mouseLocation
            self.panel.setFrameOrigin(NSPoint(
                x: origin.x + current.x - startMouse.x,
                y: origin.y + current.y - startMouse.y
            ))
        }
        actions.dragEnded = { [weak self] in
            guard let self else { return }
            self.dragStartOrigin = nil
            self.dragStartMouse = nil
            self.clampToScreen()
            self.saveFrame()
        }

        let hosting = NSHostingView(rootView: CompactView(store: store, actions: actions))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        restoreFrame()
        bindLayoutChanges()
        refreshLayout()

        dragObserver = NotificationCenter.default.addObserver(
            forName: .panelDragEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.clampToScreen()
            self.saveFrame()
        }
    }

    // MARK: - 显示 / 隐藏

    func show() {
        if !hasRestoredFrame {
            applyDefaultPosition()
            hasRestoredFrame = true
        }
        refreshLayout()
        panel.orderFrontRegardless()
        clampToScreen()
        Log.write("浮窗显示: \(Int(panel.frame.width))x\(Int(panel.frame.height))")
        onVisibilityChange?(true)
    }

    func hide() {
        panel.orderOut(nil)
        onVisibilityChange?(false)
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    // MARK: - 布局

    private func bindLayoutChanges() {
        store.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLayout() }
            .store(in: &cancellables)

        AppConfig.shared.$enabledProviders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLayout() }
            .store(in: &cancellables)
    }

    /// 根据 AI 行数调整窗口高度，并保持顶部位置不变
    private func refreshLayout() {
        let rows = CompactRows.models(
            tasks: store.tasks,
            enabled: AppConfig.shared.enabledProviders
        ).count
        let size = CompactLayout.panelSize(rows: rows)
        let old = panel.frame
        guard old.width != size.width || old.height != size.height else { return }

        let frame = NSRect(
            x: old.origin.x,
            y: old.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true, animate: false)
        if panel.isVisible { clampToScreen() }
    }

    // MARK: - 位置

    private func applyDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 20,
            y: visible.maxY - size.height - 12
        ))
    }

    private func restoreFrame() {
        guard let raw = UserDefaults.standard.string(forKey: frameKey) else { return }
        let stored = NSRectFromString(raw)
        guard stored.width > 50, stored.height > 30 else { return }

        // 尺寸以当前内容为准，只恢复位置
        let frame = NSRect(origin: stored.origin, size: panel.frame.size)
        let intersects = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard intersects else { return }

        panel.setFrame(frame, display: false)
        hasRestoredFrame = true
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }

    /// 保证窗口至少有一部分留在屏幕内
    private func clampToScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        let size = panel.frame.size
        let minVisible: CGFloat = 60

        origin.x = min(origin.x, visible.maxX - minVisible)
        origin.x = max(origin.x, visible.minX - size.width + minVisible)
        origin.y = min(origin.y, visible.maxY - minVisible)
        origin.y = max(origin.y, visible.minY - size.height + minVisible)
        panel.setFrameOrigin(origin)
    }
}
