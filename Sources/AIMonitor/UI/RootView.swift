import SwiftUI
import AppKit

// MARK: - 状态仓库

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AITask] = []
    @Published private(set) var lastUpdated = Date()
    @Published var banner: AITask?
    @Published private(set) var unreadCompletions = 0

    private var bannerToken = UUID()

    var counts: TaskCounts { TaskCounts(tasks: tasks) }

    var groups: [TaskGroup] {
        var order: [String] = []
        var buckets: [String: [AITask]] = [:]
        for task in tasks {
            if buckets[task.provider] == nil { order.append(task.provider) }
            buckets[task.provider, default: []].append(task)
        }
        return order.map { TaskGroup(provider: $0, tasks: buckets[$0] ?? []) }
    }

    func apply(_ tasks: [AITask]) {
        self.tasks = tasks
        lastUpdated = Date()
    }

    func showCompletion(_ task: AITask) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            banner = task
        }
        unreadCompletions += 1
        let token = UUID()
        bannerToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self, self.bannerToken == token else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.banner = nil }
        }
    }

    func dismissBanner() {
        bannerToken = UUID()
        withAnimation(.easeInOut(duration: 0.2)) { banner = nil }
    }

    func clearUnread() {
        unreadCompletions = 0
    }

}

// MARK: - 浮窗动作

final class PanelActions: ObservableObject {
    var hide: () -> Void = {}
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}
    var dragBegan: () -> Void = {}
    var dragChanged: (CGSize) -> Void = { _ in }
    var dragEnded: () -> Void = {}
}

// MARK: - 浮窗根视图

struct RootView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var actions: PanelActions

    private var subtitle: String {
        let active = store.counts.running + store.counts.waiting
        let time = DateFormatter.localizedString(from: store.lastUpdated, dateStyle: .none, timeStyle: .short)
        return "\(active) 个进行中 · \(time) 更新"
    }

    var body: some View {
        panel
            .padding(Theme.outerMargin)
            .shadow(color: .black.opacity(0.30), radius: 14, y: 5)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            SummaryBar(counts: store.counts)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            if let banner = store.banner {
                CompletionBanner(task: banner, onClose: { store.dismissBanner() })
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Divider().opacity(0.35)
            content
            footer
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(VisualEffectBackground(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Color(red: 0.65, green: 0.45, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("AI 任务监控")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)

            Spacer(minLength: 4)

            iconButton("gearshape", help: "设置要监控的 AI") { actions.openSettings() }
            iconButton("arrow.clockwise", help: "立即刷新") { actions.refresh() }
            iconButton("xmark", help: "关闭浮窗（菜单栏继续运行）") { actions.hide() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 5) {
                if store.tasks.isEmpty {
                    EmptyStateView(onOpenSettings: { actions.openSettings() })
                } else {
                    ForEach(store.groups) { group in
                        GroupHeader(provider: group.provider, count: group.tasks.count)
                        ForEach(group.tasks) { task in
                            TaskRow(task: task, now: store.lastUpdated)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 8))
            Text("菜单栏图标可快速查看 · 关闭浮窗不会退出")
                .font(.system(size: 9))
            Spacer(minLength: 0)
            if store.unreadCompletions > 0 {
                Text("\(store.unreadCompletions) 个完成")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.completed)
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging { isDragging = true; actions.dragBegan() }
                actions.dragChanged(value.translation)
            }
            .onEnded { _ in
                isDragging = false
                actions.dragEnded()
            }
    }

    @State private var isDragging = false

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 21, height: 21)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
