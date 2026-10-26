import SwiftUI
import AppKit

/// 主界面：完整任务列表（原浮窗内容迁到这里）
struct MainView: View {
    @ObservedObject var store: TaskStore
    let onRefresh: () -> Void
    let onSettings: () -> Void

    private var subtitle: String {
        let active = store.counts.running + store.counts.waiting
        let time = DateFormatter.localizedString(from: store.lastUpdated, dateStyle: .none, timeStyle: .short)
        return "\(active) 个进行中 · \(store.counts.total) 个任务 · \(time) 更新"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let banner = store.banner {
                CompletionBanner(task: banner, onClose: { store.dismissBanner() })
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            SummaryBar(counts: store.counts)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.10), lineWidth: 0.8)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            content
            footer
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("全部任务")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Spacer()

            Button(action: onRefresh) {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)

            Button(action: onSettings) {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Theme.accent, Color(red: 0.56, green: 0.34, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 6) {
                if store.tasks.isEmpty {
                    EmptyStateView(onOpenSettings: onSettings)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                } else {
                    ForEach(store.groups) { group in
                        GroupHeader(provider: group.provider, count: group.tasks.count)
                        ForEach(group.tasks) { task in
                            TaskRow(task: task, now: store.lastUpdated)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 9))
            Text("只读取本机会话记录，不会上传任何内容")
                .font(.system(size: 10))
            Spacer()
            Text("关闭窗口后菜单栏继续运行")
                .font(.system(size: 10))
            if store.unreadCompletions > 0 {
                Text("· \(store.unreadCompletions) 个新完成")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.completed)
            }
        }
        .foregroundStyle(Theme.inkTertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.62))
    }
}
