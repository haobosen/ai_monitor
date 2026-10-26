import Foundation

/// DeepSeek Harness（dsh）适配器
///
/// 数据来自 `~/.dsh/storages/session_projcache/sessions/session-*.json`。
/// 这是 dsh 自己维护的会话投影缓存（未压缩 JSON），包含标题、当前轮次、
/// 步骤状态、待回答问题等信息，比解压 `session.v4.jsonl.zstd` 轻量得多。
enum DSHAdapter {

    private static let activeWindow: TimeInterval = 12 * 60 * 60      // 活跃/未收尾会话最多看 12 小时
    private static let historyWindow: TimeInterval = 6 * 60 * 60      // 已完成会话保留 6 小时
    private static let idleWaitingThreshold: TimeInterval = 180       // 超过 3 分钟没有进展 → 需要操作

    private static var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/storages/session_projcache/sessions")
    }

    static func scan() -> [AITask] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let now = Date()
        var tasks: [AITask] = []

        for url in files where url.pathExtension.lowercased() == "json" {
            guard let task = parse(url: url, now: now) else { continue }
            tasks.append(task)
        }

        // 活跃任务全部保留；已完成的只留最近的几条，避免历史记录刷屏
        let active = tasks.filter { $0.status.isActive }
        let history = tasks
            .filter { !$0.status.isActive }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)

        return active + history
    }

    // MARK: - 单个会话

    private static func parse(url: URL, now: Date) -> AITask? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = root["record"] as? [String: Any],
              let rows = record["rows"] as? [String: Any] else { return nil }

        let identity = record["identity"] as? [String: Any]
        let cwd = identity?["cwd"] as? String ?? ""
        let sessionId = url.deletingPathExtension().lastPathComponent

        let title = value(rows, "title") as? String
        let listMeta = value(rows, "sessionListMetadata") as? [String: Any]
        let lastPromptAt = double(listMeta?["lastPromptAt"])
        let outline = value(rows, "turnOutline") as? [String: Any]
        let turns = outline?["turns"] as? [[String: Any]]
        let lastTurn = turns?.last
        let lastPrompt = lastTurn?["prompt"] as? String
        let lastResponse = lastTurn?["response"] as? String ?? ""

        // 空白会话（只打开过、没提问）不展示
        let isBlank = listMeta?["blank"] as? Bool ?? false
        if isBlank, lastPrompt?.isEmpty ?? true { return nil }

        let boundary = value(rows, "turnBoundary") as? [String: Any]
        let openTurn = int(boundary?["openTurnStartSeq"])
        let lastTurnNumber = int(boundary?["lastTurn"]) ?? 0
        let lastBoundary = boundary?["lastStepBoundary"] as? [String: Any]
        let boundaryKind = lastBoundary?["kind"] as? String

        let stats = value(rows, "sessionStats") as? [String: Any]
        let openStep = stats?["openStep"] as? [String: Any]
        let questions = value(rows, "userQuestions") as? [String: Any]
        let activeQuestions = (questions?["questions"] as? [String: Any])?["active"] as? [Any] ?? []

        let retry = value(rows, "llmRetry") as? [String: Any] ?? [:]
        let goal = value(rows, "goal") as? [String: Any]
        let goalFailure = goal?["failure"]
        let hasGoalFailure = !(goalFailure is NSNull) && goalFailure != nil

        // 最近一次活动时间：轮次开始、步骤开始、最后消息、缓存文件修改时间取最大
        var activity = fileModificationDate(url) ?? now
        for candidate in [
            double(openStep?["startTime"]),
            double((value(rows, "timeContext") as? [String: Any])?["lastMessageTime"]),
            lastPromptAt,
        ].compactMap({ $0 }) {
            let date = Date(timeIntervalSince1970: candidate / 1000)
            if date > activity { activity = date }
        }

        let isOpen = openTurn != nil
        let age = now.timeIntervalSince(activity)

        // 太旧的会话不再展示
        if isOpen, age > activeWindow { return nil }
        if !isOpen, age > historyWindow { return nil }

        let status: TaskStatus
        let reason: String

        if !activeQuestions.isEmpty {
            status = .waiting
            reason = "等待你回答问题"
        } else if !retry.isEmpty {
            status = .failed
            reason = "请求失败，正在重试"
        } else if hasGoalFailure {
            status = .failed
            reason = "执行失败"
        } else if boundaryKind == "error" || boundaryKind == "aborted" {
            status = .failed
            reason = "执行中断"
        } else if isOpen {
            if age > idleWaitingThreshold {
                status = .waiting
                reason = "等待确认或长时间无响应"
            } else {
                status = .running
                reason = openStep == nil ? "正在执行" : "正在处理第 \(int(openStep?["step"]) ?? 0) 步"
            }
        } else if lastTurnNumber > 0 {
            status = .completed
            reason = "已完成"
        } else {
            return nil
        }

        // 进行中的会话展示“这一轮在做什么”；已结束的会话用 dsh 生成的会话标题更准确
        let displayTitle: String
        let promptTitle = lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isOpen, !promptTitle.isEmpty {
            displayTitle = AITask.truncate(promptTitle, 90)
        } else if let title, !title.isEmpty {
            displayTitle = title
        } else if !promptTitle.isEmpty {
            displayTitle = AITask.truncate(promptTitle, 90)
        } else if !lastResponse.isEmpty {
            displayTitle = AITask.truncate(lastResponse, 90)
        } else {
            displayTitle = sessionId
        }

        let modelSelection = value(rows, "modelSelection") as? [String: Any]
        let lastUsed = modelSelection?["lastUsed"] as? [String: Any]
        let model = lastUsed?["model"] as? String
        let detail = [model, reason].compactMap { $0 }.joined(separator: " · ")

        return AITask(
            id: "dsh:\(sessionId)",
            provider: "DeepSeek Harness",
            title: displayTitle,
            project: cwd,
            status: status,
            detail: detail,
            updatedAt: activity,
            pid: nil,
            sourcePath: url.path,
            isHistorical: status == .completed
        )
    }

    // MARK: - JSON 取值

    private static func value(_ rows: [String: Any], _ key: String) -> Any? {
        guard let row = rows[key] as? [String: Any] else { return nil }
        let val = row["val"]
        return val is NSNull ? nil : val
    }

    private static func double(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        return number.doubleValue
    }

    private static func int(_ any: Any?) -> Int? {
        guard let number = any as? NSNumber else { return nil }
        return number.intValue
    }

    private static func fileModificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
