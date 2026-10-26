import SwiftUI
import AppKit

/// 全局任务状态仓库
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AITask] = []
    @Published private(set) var lastUpdated = Date()
    @Published var banner: AITask?
    @Published private(set) var unreadCompletions = 0
    /// 刚完成任务的 AI，用于浮窗上短暂高亮
    @Published private(set) var highlightedProvider: String?

    private var bannerToken = UUID()
    private var highlightToken = UUID()

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

    /// 浮窗上短暂高亮该 AI，提示“刚刚完成了一个任务”
    func highlight(provider: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            highlightedProvider = provider
        }
        let token = UUID()
        highlightToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.highlightToken == token else { return }
            withAnimation(.easeInOut(duration: 0.4)) { self.highlightedProvider = nil }
        }
    }
}

/// 小型浮窗可用的动作
final class PanelActions: ObservableObject {
    var hide: () -> Void = {}
    var openMain: (String?) -> Void = { _ in }
}
