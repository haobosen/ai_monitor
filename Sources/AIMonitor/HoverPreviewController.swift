import AppKit
import SwiftUI

/// 悬停浮窗 AI 行时，在浮窗旁边弹出的任务气泡
final class HoverPreviewController {

    private var panel: NSPanel?
    private var hosting: NSHostingView<TaskHoverPreview>?
    private var currentProvider: String?
    private var currentTasks: [AITask] = []
    private var currentSignature = ""
    private var anchorRect: NSRect = .zero
    private var onOpen: (() -> Void)?
    private var trackingTimer: Timer?
    private var outsideSince: Date?

    private let bubbleWidth: CGFloat = 300
    private let shadowPadding: CGFloat = 10
    private let gap: CGFloat = 8

    var provider: String? { currentProvider }
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(provider: String,
              tasks: [AITask],
              anchor: NSRect,
              onOpen: @escaping () -> Void,
              trackMouse: Bool = true) {
        let signature = Self.signature(for: tasks)
        let contentChanged = provider != currentProvider || signature != currentSignature
        let anchorChanged = anchor != anchorRect

        currentProvider = provider
        currentTasks = tasks
        currentSignature = signature
        anchorRect = anchor
        self.onOpen = onOpen

        if panel == nil { makePanel() }
        if hosting == nil || contentChanged {
            rebuildContent()
        }
        if contentChanged || anchorChanged || hosting == nil {
            position()
        }

        panel?.orderFrontRegardless()
        outsideSince = nil
        if trackMouse {
            startTracking()
        } else {
            trackingTimer?.invalidate()
            trackingTimer = nil
        }
    }

    func update(provider: String, tasks: [AITask], anchor: NSRect) {
        guard isVisible, provider == currentProvider else { return }
        let signature = Self.signature(for: tasks)
        let contentChanged = signature != currentSignature
        let anchorChanged = anchor != anchorRect

        currentTasks = tasks
        currentSignature = signature
        anchorRect = anchor
        if contentChanged { rebuildContent() }
        if contentChanged || anchorChanged { position() }
        outsideSince = nil
    }

    func hide() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        outsideSince = nil
        panel?.orderOut(nil)
    }

    /// 只比较气泡里真正显示的内容，避免 updatedAt 每 2 秒变化导致气泡重建/闪烁
    private static func signature(for tasks: [AITask]) -> String {
        tasks.map {
            "\($0.id)\u{1F}\($0.status.rawValue)\u{1F}\($0.title)\u{1F}\($0.project)"
        }.joined(separator: "\n")
    }

    // MARK: - 面板

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: bubbleWidth + shadowPadding * 2, height: 200),
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
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        self.panel = panel
    }

    private func rebuildContent() {
        guard let panel, let provider = currentProvider else { return }

        let view = TaskHoverPreview(
            provider: provider,
            tasks: currentTasks,
            onOpen: { [weak self] in
                self?.onOpen?()
                self?.hide()
            }
        )
        let hosting = NSHostingView(rootView: view)
        let width = bubbleWidth + shadowPadding * 2
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        hosting.layoutSubtreeIfNeeded()

        let fitted = hosting.fittingSize
        let height = min(max(fitted.height, 70), 520)
        let size = NSSize(width: width, height: height)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)
        hosting.layoutSubtreeIfNeeded()
        self.hosting = hosting
    }

    // MARK: - 定位

    private func position() {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: anchorRect.midX, y: anchorRect.midY))
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        // 优先放在 AI 行右侧；右侧放不下就放左侧
        var x = anchorRect.maxX + gap - shadowPadding
        var y = anchorRect.midY - size.height / 2

        if x + size.width > visible.maxX - 4 {
            x = anchorRect.minX - gap - size.width + shadowPadding
        }

        if x < visible.minX + 4 {
            // 左右都没有空间，放到行的下方（再不行放上方）
            x = min(max(anchorRect.midX - size.width / 2, visible.minX + 4),
                    visible.maxX - size.width - 4)
            y = anchorRect.minY - size.height - gap
            if y < visible.minY + 4 {
                y = anchorRect.maxY + gap
            }
        }

        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 鼠标移出后自动收起

    private func startTracking() {
        guard trackingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.trackMouse()
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func trackMouse() {
        guard let panel, panel.isVisible else {
            hide()
            return
        }
        let mouse = NSEvent.mouseLocation
        let inside = anchorRect.contains(mouse) || panel.frame.contains(mouse)
        guard !inside else {
            outsideSince = nil
            return
        }

        if outsideSince == nil {
            outsideSince = Date()
        } else if Date().timeIntervalSince(outsideSince!) > 0.35 {
            hide()
        }
    }
}

// MARK: - 气泡内容

struct TaskHoverPreview: View {
    let provider: String
    let tasks: [AITask]
    let onOpen: () -> Void

    private var visibleTasks: [AITask] {
        Array(sortedTasks.prefix(6))
    }

    private var sortedTasks: [AITask] {
        tasks.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private var statusColor: Color {
        let counts = TaskCounts(tasks: tasks)
        guard counts.total > 0 else { return Color.black.opacity(0.25) }
        return Theme.color(for: CompactStatusSummary.describe(counts).color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.6)
                .padding(.bottom, 2)

            if tasks.isEmpty {
                Text("这个 AI 还没有任务")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                    }
                }
                if tasks.count > visibleTasks.count {
                    Button(action: onOpen) {
                        Text("还有 \(tasks.count - visibleTasks.count) 个任务，点击查看全部")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .padding(10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(provider)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 8)

            Text(tasks.isEmpty ? "空闲" : "\(tasks.count) 个任务")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.bottom, 8)
    }

    private func taskRow(_ task: AITask) -> some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 7) {
                PreviewStatusGlyph(status: task.status)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(task.status == .completed ? Color.black : Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text(task.projectName)
                            .lineLimit(1)
                        Text("·")
                        Text(RelativeTime.string(Date().timeIntervalSince(task.updatedAt)))
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkTertiary)
                }

                Spacer(minLength: 4)

                Text(task.status.label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.color(for: task.status))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Theme.color(for: task.status).opacity(0.10))
                    )
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PreviewStatusGlyph: View {
    let status: TaskStatus

    var body: some View {
        Group {
            if status == .running {
                LoadingRing(size: 9, lineWidth: 1.5)
            } else {
                Image(systemName: status.symbolName)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.color(for: status))
            }
        }
        .frame(width: 12, height: 12)
    }
}
