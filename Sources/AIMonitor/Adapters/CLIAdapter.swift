import Foundation

/// 通用 AI CLI 适配器：兜底监控 Claude Code / Codex 之外、以命令行方式运行的 AI 工具
/// （Gemini CLI、Aider、Ollama、Cursor Agent、OpenCode……）
final class CLIAdapter {

    func scan(excluding excludedPIDs: Set<pid_t>,
              representedProviders: Set<String>,
              enabledMatches: Set<String>) -> [AITask] {
        guard !enabledMatches.isEmpty else { return [] }
        let processes = ProcessProbe.aiCLIProcesses(excluding: excludedPIDs)
        var seen = Set<String>()
        var tasks: [AITask] = []

        for process in processes {
            guard let match = ProcessProbe.match(for: process) else { continue }
            guard enabledMatches.contains(match.match) else { continue }
            let provider = match.provider
            // 已由结构化适配器覆盖的 AI（例如正在跑的 Codex 会话），不再重复展示
            if representedProviders.contains(provider) { continue }

            let command = process.arguments.dropFirst().joined(separator: " ")
            let title = command.isEmpty ? provider : "\(provider) · \(command)"
            let key = "\(provider)|\(title)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            tasks.append(AITask(
                id: "cli:\(process.pid)",
                provider: provider,
                title: AITask.truncate(title, 70),
                project: "—",
                status: .running,
                detail: "PID \(process.pid) · CLI 进程",
                updatedAt: Date(),
                pid: process.pid,
                sourcePath: process.executable,
                isHistorical: false
            ))
        }
        return tasks
    }
}
