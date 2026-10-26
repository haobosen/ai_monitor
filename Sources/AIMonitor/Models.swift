import Foundation

// MARK: - 任务状态

enum TaskStatus: String, Codable, CaseIterable {
    case running
    case waiting
    case failed
    case completed

    var label: String {
        switch self {
        case .running:   return "运行中"
        case .waiting:   return "需要操作"
        case .failed:    return "失败"
        case .completed: return "已完成"
        }
    }

    /// 菜单栏 / 文本场景用的彩色圆点
    var emoji: String {
        switch self {
        case .running:   return "🔵"
        case .waiting:   return "🟠"
        case .failed:    return "🔴"
        case .completed: return "🟢"
        }
    }

    var symbolName: String {
        switch self {
        case .running:   return "circle.dotted"
        case .waiting:   return "hand.raised.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    /// 排序优先级：需要操作 > 运行中 > 失败 > 已完成
    var priority: Int {
        switch self {
        case .waiting:   return 0
        case .running:   return 1
        case .failed:    return 2
        case .completed: return 3
        }
    }

    var isActive: Bool { self == .running || self == .waiting }
}

// MARK: - 任务

struct AITask: Identifiable, Equatable {
    /// 稳定 id：会话文件 / 进程，保证状态变化时能对上号
    let id: String
    /// 归属的 AI，例如 "Claude Code" / "Codex" / "Gemini CLI"
    let provider: String
    var title: String
    var project: String
    var status: TaskStatus
    var detail: String
    var updatedAt: Date
    var pid: Int32?
    var sourcePath: String?
    /// 进程已结束、仅作为历史记录展示
    var isHistorical: Bool = false

    var projectName: String {
        if project.isEmpty || project == "—" { return "—" }
        let url = URL(fileURLWithPath: project)
        let last = url.lastPathComponent
        return last.isEmpty ? project : last
    }

    static func truncate(_ text: String, _ limit: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)) + "…"
    }

    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - 分组

struct TaskGroup: Identifiable {
    let provider: String
    var tasks: [AITask]
    var id: String { provider }
}

// MARK: - 状态汇总

struct TaskCounts {
    var running = 0
    var waiting = 0
    var failed = 0
    var completed = 0

    var total: Int { running + waiting + failed + completed }

    init(tasks: [AITask]) {
        for task in tasks {
            switch task.status {
            case .running:   running += 1
            case .waiting:   waiting += 1
            case .failed:    failed += 1
            case .completed: completed += 1
            }
        }
    }
}
