import Foundation
import Darwin

/// 轻量进程探测：不依赖 `ps`（沙箱 / 权限受限环境下也能用）
enum ProcessProbe {

    struct CLIProcess {
        let pid: pid_t
        let executable: String
        let arguments: [String]
        var executableName: String { (executable as NSString).lastPathComponent }
        var joinedCommand: String { arguments.joined(separator: " ") }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    static func listPIDs() -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        return buffer.prefix(count).filter { $0 > 0 }
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &buffer, 4096)
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    /// 从 KERN_PROCARGS2 读取命令行参数
    static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { raw in
            raw.copyBytes(from: buffer[0..<MemoryLayout<Int32>.size])
        }
        guard argc > 0 else { return [] }

        var index = MemoryLayout<Int32>.size
        // 跳过可执行文件路径
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var result: [String] = []
        var start = index
        while index < buffer.count, result.count < Int(argc) {
            if buffer[index] == 0 {
                if start < index {
                    result.append(String(decoding: buffer[start..<index], as: UTF8.self))
                }
                start = index + 1
            }
            index += 1
        }
        return result
    }

    static func process(pid: pid_t) -> CLIProcess? {
        guard let path = executablePath(of: pid) else { return nil }
        return CLIProcess(pid: pid, executable: path, arguments: arguments(of: pid))
    }

    /// 校验 pid 确实是某个 AI CLI，避免 pid 复用造成误报
    static func looksLikeClaude(_ process: CLIProcess) -> Bool {
        process.executable.contains("/claude")
            || process.executableName == "claude"
            || process.arguments.first?.contains("/claude") == true
    }

    static func looksLikeCodex(_ process: CLIProcess) -> Bool {
        process.executableName == "codex"
            || process.arguments.first?.hasSuffix("/codex") == true
    }

    /// 我们支持的 AI CLI 关键词 → 展示名
    static let knownCLI: [(match: String, provider: String)] = [
        ("claude", "Claude Code"),
        ("codex", "Codex"),
        ("gemini", "Gemini CLI"),
        ("aider", "Aider"),
        ("cursor-agent", "Cursor Agent"),
        ("opencode", "OpenCode"),
        ("qwen", "Qwen Code"),
        ("goose", "Goose"),
        ("crush", "Crush"),
        ("amp", "Amp"),
        ("ollama", "Ollama"),
        ("llm", "LLM"),
        ("sgpt", "ShellGPT"),
    ]

    static func aiCLIProcesses(excluding excludedPIDs: Set<pid_t>) -> [CLIProcess] {
        var matches: [CLIProcess] = []
        let ownPID = getpid()
        for pid in listPIDs() where pid != ownPID && !excludedPIDs.contains(pid) {
            // 先只取可执行路径，命中才读取命令行，避免对所有进程做一次 sysctl
            guard let path = executablePath(of: pid) else { continue }
            let name = (path as NSString).lastPathComponent.lowercased()
            guard knownCLI.contains(where: { name == $0.match || name.hasPrefix($0.match + "-") }) else { continue }
            matches.append(CLIProcess(pid: pid, executable: path, arguments: arguments(of: pid)))
        }
        return matches
    }

    static func match(for process: CLIProcess) -> (match: String, provider: String)? {
        let name = process.executableName.lowercased()
        return knownCLI.first { name == $0.match || name.hasPrefix($0.match + "-") }
    }

    static func providerName(for process: CLIProcess) -> String? {
        match(for: process)?.provider
    }
}
