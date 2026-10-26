import Foundation

/// 监控引擎：定时把各个 AI 适配器的结果汇总成统一任务列表
final class MonitorEngine {

    private let claudeAdapter = ClaudeAdapter()
    private let codexAdapter = CodexAdapter()
    private let cliAdapter = CLIAdapter()

    private let queue = DispatchQueue(label: "com.haobosen.aimonitor.scan", qos: .userInitiated)
    private var timer: Timer?
    private var scanning = false
    private var enabledProviders: Set<String> = AppConfig.defaultProviders

    /// 主线程回调
    var onUpdate: (([AITask]) -> Void)?

    func setEnabledProviders(_ providers: Set<String>) {
        enabledProviders = providers
        refresh()
    }

    func start(interval: TimeInterval = 2.0) {
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true

        queue.async { [weak self] in
            guard let self else { return }
            let tasks = self.scanOnce()
            DispatchQueue.main.async {
                self.scanning = false
                self.onUpdate?(tasks)
            }
        }
    }

    private func scanOnce() -> [AITask] {
        var tasks: [AITask] = []
        if enabledProviders.contains("claude") { tasks += claudeAdapter.scan() }
        if enabledProviders.contains("codex") { tasks += codexAdapter.scan() }

        let cliMatches = Set(enabledProviders.compactMap { id -> String? in
            id.hasPrefix("cli:") ? String(id.dropFirst(4)) : nil
        })
        let represented = Set(tasks.filter { $0.status.isActive }.map { $0.provider })
        let excludedPIDs = Set(tasks.compactMap { $0.pid })
        tasks += cliAdapter.scan(
            excluding: excludedPIDs,
            representedProviders: represented,
            enabledMatches: cliMatches
        )

        // 合并 / 去重
        var merged: [String: AITask] = [:]
        for task in tasks {
            if let existing = merged[task.id] {
                if task.updatedAt > existing.updatedAt { merged[task.id] = task }
            } else {
                merged[task.id] = task
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// headless 模式（--dump）使用，不启动定时器
    static func scanAll() -> [AITask] {
        var tasks = ClaudeAdapter().scan() + CodexAdapter().scan()
        let represented = Set(tasks.filter { $0.status.isActive }.map { $0.provider })
        let excludedPIDs = Set(tasks.compactMap { $0.pid })
        let allCLI = Set(ProcessProbe.knownCLI.map { $0.match })
        tasks += CLIAdapter().scan(
            excluding: excludedPIDs,
            representedProviders: represented,
            enabledMatches: allCLI
        )

        var merged: [String: AITask] = [:]
        for task in tasks {
            if let existing = merged[task.id] {
                if task.updatedAt > existing.updatedAt { merged[task.id] = task }
            } else {
                merged[task.id] = task
            }
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
