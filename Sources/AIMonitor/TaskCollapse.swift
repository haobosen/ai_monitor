import Foundation

/// 同一 AI 下，同一个项目只保留最新的一次对话。
/// 旧会话没有被删除，只是不再出现在主界面 / 浮窗 / 悬停气泡里。
enum TaskCollapse {

    static func latestPerProject(_ tasks: [AITask]) -> [AITask] {
        var selected: [String: AITask] = [:]
        var order: [String] = []

        for task in tasks {
            let key = groupKey(for: task)
            if let existing = selected[key] {
                if isNewer(task, than: existing) {
                    selected[key] = task
                }
            } else {
                selected[key] = task
                order.append(key)
            }
        }

        let collapsed = order.compactMap { selected[$0] }
        return collapsed.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    /// 没有项目路径的任务不参与项目合并，避免把不相关的命令行任务吞掉
    private static func groupKey(for task: AITask) -> String {
        var project = task.project.trimmingCharacters(in: .whitespacesAndNewlines)
        while project.hasSuffix("/"), project.count > 1 {
            project.removeLast()
        }

        if !project.isEmpty, project != "—" {
            return "project\u{1F}\(task.provider)\u{1F}\(project)"
        }
        return "task\u{1F}\(task.id)"
    }

    private static func isNewer(_ lhs: AITask, than rhs: AITask) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.status.isActive != rhs.status.isActive {
            return lhs.status.isActive
        }
        return lhs.id < rhs.id
    }
}
