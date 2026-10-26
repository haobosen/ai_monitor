import SwiftUI
import AppKit

/// 小型浮窗：只列出正在监控的 AI 及其状态摘要，不展示具体任务
struct CompactView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var actions: PanelActions
    @ObservedObject private var config = AppConfig.shared

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
                    .onTapGesture { actions.openMain(row.provider) }
                }
            }
        }
        .frame(width: CompactLayout.cardWidth, height: CompactLayout.cardHeight(rows: rows.count))
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7)
        )
        .padding(CompactLayout.shadowPadding)
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 6.5))
                    .foregroundStyle(Color.black.opacity(0.32))
                Text("AI 任务监控")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            Button { actions.openMain(nil) } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("打开主界面")

            Button { actions.hide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.35))
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
                .foregroundStyle(Color.black.opacity(0.4))
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
            Group {
                if isIdle {
                    Circle()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: 7, height: 7)
                } else if summary.color == .running {
                    LoadingRing(size: 9, lineWidth: 1.5)
                } else {
                    Circle()
                        .fill(Theme.color(for: summary.color))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 10, height: 10)

            Text(row.provider)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isIdle ? Color.black.opacity(0.45) : Color.black.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(summary.text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isIdle ? Color.black.opacity(0.4) : Theme.color(for: summary.color))
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
        if hovering { return Color.black.opacity(0.05) }
        return .clear
    }
}
