import Foundation

// MARK: - 小型浮窗的行模型（只到 AI 粒度）

struct CompactRowModel: Identifiable {
    let id: String
    let provider: String
    let counts: TaskCounts
}

enum CompactRows {

    /// 按“用户选择监控的 AI”生成浮窗行；没有任务的 AI 也保留一行，显示为空闲
    static func models(tasks: [AITask], enabled: Set<String>) -> [CompactRowModel] {
        let ids = enabled.sorted { lhs, rhs in
            let left = AIProviderCatalog.sortIndex(for: lhs)
            let right = AIProviderCatalog.sortIndex(for: rhs)
            if left != right { return left < right }
            return AIProviderCatalog.displayName(for: lhs) < AIProviderCatalog.displayName(for: rhs)
        }

        return ids.map { id in
            let name = AIProviderCatalog.displayName(for: id)
            let matched = tasks.filter { $0.provider == name }
            return CompactRowModel(id: id, provider: name, counts: TaskCounts(tasks: matched))
        }
    }
}

// MARK: - 浮窗尺寸

enum CompactLayout {
    static let cardWidth: CGFloat = 200
    static let rowHeight: CGFloat = 26
    static let headerHeight: CGFloat = 22
    static let verticalPadding: CGFloat = 5
    static let shadowPadding: CGFloat = 8

    static func cardHeight(rows: Int) -> CGFloat {
        headerHeight + CGFloat(max(rows, 1)) * rowHeight + verticalPadding * 2
    }

    static func panelSize(rows: Int) -> NSSize {
        NSSize(
            width: cardWidth + shadowPadding * 2,
            height: cardHeight(rows: rows) + shadowPadding * 2
        )
    }
}

// MARK: - 行状态摘要

enum CompactStatusSummary {
    /// 返回：状态色、右侧文案
    static func describe(_ counts: TaskCounts) -> (color: TaskStatus, text: String) {
        if counts.waiting > 0 {
            return (.waiting, "\(counts.waiting) 待操作")
        }
        if counts.failed > 0 {
            return (.failed, "\(counts.failed) 失败")
        }
        if counts.running > 0 {
            return (.running, "\(counts.running) 运行")
        }
        if counts.completed > 0 {
            return (.completed, counts.completed == 1 ? "已完成" : "\(counts.completed) 已完成")
        }
        return (.completed, "空闲")
    }
}
