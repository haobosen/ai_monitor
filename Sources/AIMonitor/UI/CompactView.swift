import SwiftUI
import AppKit

/// 小型浮窗：只列出正在监控的 AI 及其状态摘要，不展示具体任务
struct CompactView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var actions: PanelActions
    @ObservedObject private var config = AppConfig.shared

    @State private var isDragging = false
    @State private var dragMoved = false

    private var rows: [CompactRowModel] {
        CompactRows.models(tasks: store.tasks, enabled: config.enabledProviders)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                emptyRow
            } else {
                ForEach(rows) { row in
                    CompactRowItem(
                        row: row,
                        highlighted: store.highlightedProvider == row.provider
                    )
                    .contentShape(Rectangle())
                    .gesture(rowGesture(for: row))
                }
            }
        }
        .frame(width: CompactLayout.cardWidth, height: CompactLayout.cardHeight(rows: rows.count))
        .background(VisualEffectBackground(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
        )
        .padding(CompactLayout.shadowPadding)
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 6.5))
                    .foregroundStyle(.tertiary)
                Text("AI 任务监控")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(WindowDragHandle())
            .gesture(headerDragGesture)

            Button { actions.openMain(nil) } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("打开主界面")

            Button { actions.hide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("隐藏浮窗（菜单栏继续运行）")
        }
        .padding(.horizontal, 9)
        .frame(height: CompactLayout.headerHeight)
    }

    private var emptyRow: some View {
        HStack {
            Text("还没有选择要监控的 AI")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("打开主界面")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 9)
        .frame(height: CompactLayout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { actions.openMain(nil) }
    }

    // MARK: - 拖动 / 点击

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    actions.dragBegan()
                }
                actions.dragChanged(value.translation)
            }
            .onEnded { _ in
                isDragging = false
                actions.dragEnded()
            }
    }

    /// 一个手势同时处理“拖动窗口”和“点击打开主界面”：
    /// 位移很小视为点击，超过阈值则拖动。
    private func rowGesture(for row: CompactRowModel) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragMoved = false
                    actions.dragBegan()
                }
                if abs(value.translation.width) + abs(value.translation.height) > 3 {
                    dragMoved = true
                }
                if dragMoved {
                    actions.dragChanged(value.translation)
                }
            }
            .onEnded { _ in
                let moved = dragMoved
                isDragging = false
                dragMoved = false
                actions.dragEnded()
                if !moved {
                    actions.openMain(row.provider)
                }
            }
    }
}

// MARK: - 单个 AI 行

struct CompactRowItem: View {
    let row: CompactRowModel
    let highlighted: Bool

    @State private var hovering = false

    private var summary: (color: TaskStatus, text: String) {
        CompactStatusSummary.describe(row.counts)
    }

    private var isIdle: Bool { row.counts.total == 0 }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.color(for: summary.color).opacity(isIdle ? 0.10 : 0.18))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(isIdle ? Color.secondary.opacity(0.5) : Theme.color(for: summary.color))
                    .frame(width: 5, height: 5)
            }

            Text(row.provider)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isIdle ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(summary.text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isIdle ? Color.secondary : Theme.color(for: summary.color))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: CompactLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fillColor)
                .padding(.horizontal, 4)
        )
        .onHover { hovering = $0 }
        .help("\(row.provider) · \(row.counts.total) 个任务，点击打开主界面")
    }

    private var fillColor: Color {
        if highlighted { return Theme.completed.opacity(0.16) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}


// MARK: - 标题栏拖动区域（AppKit）

/// 用 NSView + performDrag 实现窗口拖动，避免 SwiftUI 手势随窗口移动而失效
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            Log.write("拖动浮窗")
            window?.performDrag(with: event)
            NotificationCenter.default.post(name: .panelDragEnded, object: nil)
        }
    }
}


extension Notification.Name {
    static let panelDragEnded = Notification.Name("AIMonitorPanelDragEnded")
}
