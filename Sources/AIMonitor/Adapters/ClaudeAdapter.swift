import Foundation

/// Claude Code 适配器
///
/// 数据来源（全部为 Claude Code 自己落盘的本地数据，只读）：
/// - `~/.claude/sessions/<pid>.json`：pid → sessionId / cwd 的映射，用来判断会话是否还活着
/// - `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`：完整对话记录，用来推导任务标题与状态
final class ClaudeAdapter {

    private enum LastKind {
        case assistantText
        case assistantTool
        case toolResult
        case humanPrompt
        case error
        case unknown
    }

    private struct TailInfo {
        var title: String?
        var lastPrompt: String?
        var model: String?
        var lastKind: LastKind = .unknown
        var pendingTools: [String] = []
        var lastTimestamp: Date?
    }

    private struct SessionMeta: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String?
        let startedAt: Double?
        let version: String?
        let kind: String?
        let entrypoint: String?
        let name: String?
    }

    private let home = URL(fileURLWithPath: NSHomeDirectory())
    private var cache: [String: (stamp: String, info: TailInfo)] = [:]
    private let lock = NSLock()

    private var sessionsDirectory: URL { home.appendingPathComponent(".claude/sessions") }
    private var projectsDirectory: URL { home.appendingPathComponent(".claude/projects") }

    func scan() -> [AITask] {
        let metas = loadSessionMetas()
        guard !metas.isEmpty else { return [] }

        var liveTasks: [AITask] = []
        var historical: [AITask] = []

        for meta in metas {
            guard let transcript = transcriptURL(for: meta) else { continue }
            guard FileTail.fileSize(transcript) > 0 else { continue }

            let modified = FileTail.modificationDate(transcript) ?? Date()
            let info = tailInfo(for: transcript, modified: modified)
            let deadFor = Date().timeIntervalSince(modified)

            // 判断进程是否还在：pid 存活 + 命令行确实是 claude（防止 pid 复用误判）
            var alive = false
            if let process = ProcessProbe.process(pid: meta.pid) {
                alive = ProcessProbe.isAlive(meta.pid) && ProcessProbe.looksLikeClaude(process)
            }

            guard alive || deadFor < 6 * 3600 else { continue }

            // 只展示“当前活跃”或“最近结束”的会话，避免历史会话刷屏
            guard alive ? deadFor < 12 * 3600 : deadFor < 6 * 3600 else { continue }

            let status = resolveStatus(info: info, idle: deadFor, alive: alive)
            let title = taskTitle(info: info, meta: meta)
            let project = meta.cwd.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
            let detail = buildDetail(info: info, meta: meta, alive: alive, idle: deadFor)

            let task = AITask(
                id: "claude:\(meta.sessionId)",
                provider: "Claude Code",
                title: title,
                project: project,
                status: status,
                detail: detail,
                updatedAt: modified,
                pid: meta.pid,
                sourcePath: transcript.path,
                isHistorical: !alive
            )

            if alive { liveTasks.append(task) } else { historical.append(task) }
        }

        historical.sort { $0.updatedAt > $1.updatedAt }
        let recentHistorical = Array(historical.prefix(5))
        return (liveTasks + recentHistorical).sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - 状态推导

    private func resolveStatus(info: TailInfo, idle: TimeInterval, alive: Bool) -> TaskStatus {
        if info.lastKind == .error { return .failed }
        guard alive else { return .completed }

        switch info.lastKind {
        case .assistantText:
            // 一轮回复已经收尾，等待用户下一条指令
            return .completed
        case .assistantTool:
            // 有工具还没返回结果：短时间算运行中；长时间无写入，很可能卡在权限确认
            return idle > 180 ? .waiting : .running
        case .toolResult:
            // 工具结果已回写，模型正在继续推理
            return idle > 300 ? .waiting : .running
        case .humanPrompt:
            // 用户刚发消息、模型还没写回任何内容
            return idle > 180 ? .waiting : .running
        case .error:
            return .failed
        case .unknown:
            return idle > 120 ? .waiting : .running
        }
    }

    private func buildDetail(info: TailInfo, meta: SessionMeta, alive: Bool, idle: TimeInterval) -> String {
        var parts: [String] = []
        if let model = info.model, !model.isEmpty { parts.append(model) }
        if let entrypoint = meta.entrypoint, !entrypoint.isEmpty { parts.append(entrypoint) }
        if !alive {
            parts.append("进程已结束")
        } else if info.lastKind == .assistantTool, idle > 180 {
            parts.append("等待工具确认")
        } else {
            parts.append("\(RelativeTime.string(idle))活跃")
        }
        return parts.joined(separator: " · ")
    }

    private func taskTitle(info: TailInfo, meta: SessionMeta) -> String {
        if let title = info.title, !title.isEmpty { return AITask.truncate(title, 70) }
        if let prompt = info.lastPrompt, !prompt.isEmpty { return AITask.truncate(prompt, 70) }
        if let name = meta.name, !name.isEmpty { return name }
        if let cwd = meta.cwd { return URL(fileURLWithPath: cwd).lastPathComponent }
        return "Claude Code 会话"
    }

    // MARK: - 数据读取

    private func loadSessionMetas() -> [SessionMeta] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        var metas: [SessionMeta] = []
        for file in files where file.pathExtension == "json" {
            // 只处理最近 7 天内更新过的 session 文件
            guard let data = try? Data(contentsOf: file),
                  let meta = try? decoder.decode(SessionMeta.self, from: data) else { continue }
            metas.append(meta)
        }
        return metas
    }

    private func transcriptURL(for meta: SessionMeta) -> URL? {
        let manager = FileManager.default
        if let cwd = meta.cwd, !cwd.isEmpty {
            let encoded = cwd
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ".", with: "-")
            let candidate = projectsDirectory
                .appendingPathComponent(encoded)
                .appendingPathComponent("\(meta.sessionId).jsonl")
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }
        // 兜底：目录编码方式变化时按文件名扫描
        guard let projects = try? manager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for project in projects {
            let candidate = project.appendingPathComponent("\(meta.sessionId).jsonl")
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func tailInfo(for url: URL, modified: Date) -> TailInfo {
        let stamp = "\(modified.timeIntervalSince1970)-\(FileTail.fileSize(url))"
        lock.lock()
        if let cached = cache[url.path], cached.stamp == stamp {
            lock.unlock()
            return cached.info
        }
        lock.unlock()

        let info = parseTail(url)
        lock.lock()
        cache[url.path] = (stamp, info)
        lock.unlock()
        return info
    }

    private func parseTail(_ url: URL) -> TailInfo {
        var info = TailInfo()
        let objects = FileTail.tailObjects(at: url, maxBytes: 512 * 1024)

        for object in objects.reversed() {
            let type = object["type"] as? String

            // 标题只需要取最近的几个元信息
            if info.title == nil, type == "ai-title", let title = object["aiTitle"] as? String, !title.isEmpty {
                info.title = title
            }
            if info.lastPrompt == nil, type == "last-prompt", let prompt = object["lastPrompt"] as? String, !prompt.isEmpty {
                info.lastPrompt = prompt
            }
            if info.lastTimestamp == nil, let raw = object["timestamp"] {
                info.lastTimestamp = FileTail.date(from: raw)
            }

            if type == "assistant", info.model == nil {
                let message = object["message"] as? [String: Any]
                info.model = message?["model"] as? String
            }

            guard info.lastKind == .unknown else { continue }

            switch type {
            case "assistant":
                let message = object["message"] as? [String: Any]
                let content = message?["content"] as? [[String: Any]] ?? []
                let tools = content.compactMap { block -> String? in
                    guard block["type"] as? String == "tool_use" else { return nil }
                    return block["name"] as? String
                }
                info.pendingTools = tools
                info.lastKind = tools.isEmpty ? .assistantText : .assistantTool

            case "user":
                if object["isApiErrorMessage"] as? Bool == true {
                    info.lastKind = .error
                    break
                }
                let message = object["message"] as? [String: Any]
                let content = message?["content"] as? [[String: Any]] ?? []
                let hasToolResult = content.contains { $0["type"] as? String == "tool_result" }
                info.lastKind = hasToolResult ? .toolResult : .humanPrompt

            case "system":
                let subtype = object["subtype"] as? String
                info.lastKind = (subtype == "api_error") ? .error : .unknown

            default:
                break
            }
        }

        return info
    }
}

// MARK: - 相对时间

enum RelativeTime {
    static func string(_ seconds: TimeInterval) -> String {
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(Int(seconds)) 秒前" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }
}
