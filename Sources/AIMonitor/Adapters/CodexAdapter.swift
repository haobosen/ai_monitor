import Foundation

/// Codex（Codex CLI / Codex Desktop）适配器
///
/// 数据来源：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
/// - `session_meta` 提供会话 id、工作目录、来源
/// - `response_item` 里的 user message 用来生成任务标题
/// - `event_msg` 的 `task_started` / `task_complete` / `turn_aborted` 精确表达任务状态
///
/// 会话文件可能非常大（几百 MB），因此首次只读头尾，之后按“新增字节”增量解析。
final class CodexAdapter {

    private struct Summary {
        var title: String?
        var cwd: String?
        var model: String?
        var originator: String?
        var trigger: String?
        var lastEventType: String?
        var lastTaskAt: Date?
        var lastActivityAt: Date?
        var lastError: String?
        var isInternal = false
    }

    private struct CacheEntry {
        var size: Int
        var offset: Int
        var summary: Summary
        var pending: Data
    }

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()

    private var sessionsDirectory: URL { home.appendingPathComponent(".codex/sessions") }

    /// 我们关心的任务状态事件
    private let stateEvents: Set<String> = ["task_started", "task_complete", "turn_aborted", "error", "stream_error"]

    func scan() -> [AITask] {
        let urls = FileTail.strings(in: sessionsDirectory, extension: "jsonl", modifiedWithin: 12 * 3600)
            .sorted { (FileTail.modificationDate($0) ?? .distantPast) > (FileTail.modificationDate($1) ?? .distantPast) }
            .prefix(16)

        var tasks: [AITask] = []
        for url in urls {
            guard let modified = FileTail.modificationDate(url) else { continue }
            let summary = summary(for: url, modified: modified)

            // 系统内部会话（自动 review）不算用户任务
            if summary.isInternal { continue }
            // 没有任何任务事件的空会话
            guard let eventType = summary.lastEventType else { continue }

            let idle = Date().timeIntervalSince(summary.lastActivityAt ?? modified)
            let status = resolveStatus(eventType: eventType, summary: summary, idle: idle)
            let updatedAt = status.isActive
                ? (summary.lastActivityAt ?? modified)
                : (summary.lastTaskAt ?? modified)

            // 已完成的只保留近期记录
            if status == .completed, Date().timeIntervalSince(updatedAt) > 6 * 3600 { continue }
            if status == .failed, Date().timeIntervalSince(updatedAt) > 12 * 3600 { continue }

            let detailParts = [summary.model, summary.originator]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

            tasks.append(AITask(
                id: "codex:\(url.lastPathComponent)",
                provider: "Codex",
                title: summary.title ?? "Codex 任务",
                project: summary.cwd ?? "—",
                status: status,
                detail: detailParts.isEmpty ? "Codex" : detailParts.joined(separator: " · "),
                updatedAt: updatedAt,
                pid: nil,
                sourcePath: url.path,
                isHistorical: !status.isActive && idle > 900
            ))
        }
        return tasks
    }

    private func resolveStatus(eventType: String, summary: Summary, idle: TimeInterval) -> TaskStatus {
        switch eventType {
        case "task_complete":
            return .completed
        case "turn_aborted":
            return .failed
        case "error", "stream_error":
            return .failed
        case "task_started":
            // 近期有写入 = 正在跑；长时间无写入 = 很可能停在审批 / 等待用户
            return idle > 300 ? .waiting : .running
        default:
            return .completed
        }
    }

    // MARK: - 增量解析

    private func summary(for url: URL, modified: Date) -> Summary {
        let size = FileTail.fileSize(url)

        lock.lock()
        let cached = cache[url.path]
        lock.unlock()

        if var entry = cached {
            // 文件被截断 / 重写：整体重建
            if size < entry.offset {
                let rebuilt = rebuild(url, size: size, modified: modified)
                store(rebuilt, url: url, size: size)
                return rebuilt
            }

            // 没有新增内容
            if size == entry.offset {
                var summary = entry.summary
                summary.lastActivityAt = modified
                return summary
            }

            // 只解析新增字节
            if let appended = readRange(url, from: entry.offset, to: size) {
                var summary = entry.summary
                var pending = entry.pending
                pending.append(appended)
                let (objects, remainder) = completeObjects(&pending)
                for object in objects {
                    applyState(object, to: &summary)
                }
                summary.lastActivityAt = modified
                entry.offset = size
                entry.size = size
                entry.pending = remainder
                entry.summary = summary

                lock.lock()
                cache[url.path] = entry
                lock.unlock()
                return summary
            }
        }

        // 首次：头部 + 尾部窗口
        let rebuilt = rebuild(url, size: size, modified: modified)
        store(rebuilt, url: url, size: size)
        return rebuilt
    }

    private func store(_ summary: Summary, url: URL, size: Int) {
        lock.lock()
        cache[url.path] = CacheEntry(size: size, offset: size, summary: summary, pending: Data())
        lock.unlock()
    }

    private func rebuild(_ url: URL, size: Int, modified: Date) -> Summary {
        var summary = Summary()
        summary.lastActivityAt = modified

        // 头部：会话元信息 + 第一条有意义的用户消息
        for object in FileTail.headObjects(at: url, maxBytes: 256 * 1024) {
            applyHead(object, to: &summary)
            if summary.title != nil, summary.cwd != nil, summary.model != nil { break }
        }

        // 尾部：最后一次任务状态事件（逐步扩大窗口，兼容超长会话）
        for object in loadStateEventObjects(url) {
            applyState(object, to: &summary)
        }

        summary.lastActivityAt = max(summary.lastActivityAt ?? modified, modified)

        // 自动 review 会话（模型 codex-auto-review）不算用户任务
        if summary.model == "codex-auto-review" {
            summary.isInternal = true
        }
        return summary
    }

    private func applyHead(_ object: [String: Any], to summary: inout Summary) {
        let payload = object["payload"] as? [String: Any]
        switch object["type"] as? String {
        case "session_meta":
            summary.cwd = payload?["cwd"] as? String
            summary.originator = payload?["originator"] as? String
        case "turn_context":
            if summary.cwd == nil { summary.cwd = payload?["cwd"] as? String }
            if summary.model == nil { summary.model = payload?["model"] as? String }
        case "response_item":
            if summary.title == nil,
               payload?["type"] as? String == "message",
               payload?["role"] as? String == "user",
               let text = messageText(payload?["content"]),
               let cleaned = cleanTitle(text) {
                summary.title = AITask.truncate(cleaned, 70)
            }
        case "event_msg":
            if let settings = payload?["thread_settings"] as? [String: Any],
               summary.model == nil {
                summary.model = settings["model"] as? String
            }
        default:
            break
        }
    }

    private func applyState(_ object: [String: Any], to summary: inout Summary) {
        if let timestamp = FileTail.date(from: object["timestamp"]) {
            summary.lastActivityAt = timestamp
        }

        let payload = object["payload"] as? [String: Any]
        guard let type = payload?["type"] as? String else { return }

        if summary.model == nil, type == "thread_settings_applied" {
            let settings = payload?["thread_settings"] as? [String: Any]
            summary.model = settings?["model"] as? String
        }

        guard stateEvents.contains(type) else { return }
        let timestamp = FileTail.date(from: object["timestamp"])

        switch type {
        case "task_started":
            summary.lastEventType = "task_started"
            summary.lastError = nil
            summary.lastTaskAt = timestamp
            if let attribution = payload?["turn_attribution"] as? [String: Any] {
                summary.trigger = attribution["turn_trigger"] as? String
            }
        case "task_complete":
            summary.lastEventType = "task_complete"
            summary.lastError = nil
            summary.lastTaskAt = timestamp
        case "turn_aborted":
            summary.lastEventType = "turn_aborted"
            summary.lastError = "任务被中止"
            summary.lastTaskAt = timestamp
        case "error", "stream_error":
            summary.lastEventType = "error"
            summary.lastError = payload?["message"] as? String ?? "运行出错"
            summary.lastTaskAt = timestamp
        default:
            break
        }
    }

    /// 切出完整的 JSONL 行，返回对象与剩余的不完整行
    private func completeObjects(_ data: inout Data) -> ([[String: Any]], Data) {
        var objects: [[String: Any]] = []
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 10) {
            let line = data[start..<newline]
            if !line.isEmpty,
               let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                objects.append(object)
            }
            start = data.index(after: newline)
        }
        let remainder = Data(data[start...])
        return (objects, remainder)
    }

    private func readRange(_ url: URL, from offset: Int, to end: Int) -> Data? {
        guard end > offset, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: end - offset)
        } catch {
            return nil
        }
    }

    /// 从文件尾部逐步扩大范围，直到读到最后一次任务状态事件
    private func loadStateEventObjects(_ url: URL) -> [[String: Any]] {
        let windows = [256 * 1024, 1024 * 1024, 4 * 1024 * 1024, 12 * 1024 * 1024]
        var lastObjects: [[String: Any]] = []
        for window in windows {
            let objects = FileTail.tailObjects(at: url, maxBytes: window)
            lastObjects = objects
            let hasTaskEvent = objects.contains { object in
                guard let payload = object["payload"] as? [String: Any],
                      let type = payload["type"] as? String else { return false }
                return stateEvents.contains(type)
            }
            if hasTaskEvent { return objects }
        }
        return lastObjects
    }

    private func messageText(_ content: Any?) -> String? {
        guard let blocks = content as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "input_text" else { return nil }
            return block["text"] as? String
        }
        return texts.joined(separator: "\n")
    }

    /// 过滤掉环境上下文 / 系统注入的 XML 块，只保留真正的人类指令
    private func cleanTitle(_ text: String) -> String? {
        var cleaned = text
        let blockPatterns = [
            "<environment_context>.*?</environment_context>",
            "<external_codex_apps_open_page>.*?</external_codex_apps_open_page>",
            "<permission[^>]*>.*?</permission>",
            "<user_instructions>.*?</user_instructions>",
        ]
        for pattern in blockPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("<") { return nil }
        if cleaned.lowercased().hasPrefix("the following is the codex agent history") { return nil }
        if cleaned.lowercased().hasPrefix("you are codex") { return nil }
        return cleaned
    }
}
