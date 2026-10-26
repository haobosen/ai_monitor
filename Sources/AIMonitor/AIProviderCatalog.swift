import Foundation

/// 初始化 / 设置页里展示的可监控对象
struct DetectedAI: Identifiable, Equatable {
    enum Category {
        case agent   // 有结构化会话记录，可精确判断状态
        case cli     // 只能看到进程在跑
        case app     // 桌面应用，暂不支持任务级状态
    }

    let id: String
    let name: String
    let detail: String
    let category: Category
    let available: Bool
    let supported: Bool

    var categoryLabel: String {
        switch category {
        case .agent: return "支持任务级监控"
        case .cli:   return "支持进程级监控"
        case .app:   return "仅检测是否安装"
        }
    }
}

enum AIProviderCatalog {

    /// 把配置里的 provider id 映射成展示名（与 AITask.provider 保持一致）
    static func displayName(for id: String) -> String {
        switch id {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "dsh": return "DeepSeek Harness"
        default:
            if id.hasPrefix("cli:") {
                let match = String(id.dropFirst(4))
                return ProcessProbe.knownCLI.first(where: { $0.match == match })?.provider ?? match.capitalized
            }
            if id.hasPrefix("app:") {
                return String(id.dropFirst(4))
            }
            return id
        }
    }

    /// 浮窗里的固定顺序：Claude Code、Codex，然后其他 CLI
    static func sortIndex(for id: String) -> Int {
        if id == "claude" { return 0 }
        if id == "codex" { return 1 }
        if id == "dsh" { return 2 }
        if id.hasPrefix("cli:") { return 3 }
        return 4
    }

    /// 扫描本机已安装 / 正在运行的 AI 工具
    static func discover() -> [DetectedAI] {
        var result: [DetectedAI] = []

        // 1. Claude Code
        let claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        let claudeAvailable = FileManager.default.fileExists(atPath: claudeDir.path)
        result.append(DetectedAI(
            id: "claude",
            name: "Claude Code",
            detail: claudeAvailable
                ? "读取 ~/.claude 会话记录，可识别运行 / 完成 / 失败"
                : "未检测到 ~/.claude 目录",
            category: .agent,
            available: claudeAvailable,
            supported: claudeAvailable
        ))

        // 2. Codex
        let codexDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        let codexAvailable = FileManager.default.fileExists(atPath: codexDir.appendingPathComponent("sessions").path)
        result.append(DetectedAI(
            id: "codex",
            name: "Codex",
            detail: codexAvailable
                ? "读取 ~/.codex 会话记录，可识别运行 / 完成 / 失败"
                : "未检测到 ~/.codex 会话目录",
            category: .agent,
            available: codexAvailable,
            supported: codexAvailable
        ))

        // 3. DeepSeek Harness（dsh）
        let dshCache = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".dsh/storages/session_projcache/sessions")
        let dshAvailable = FileManager.default.fileExists(atPath: dshCache.path)
        result.append(DetectedAI(
            id: "dsh",
            name: "DeepSeek Harness",
            detail: dshAvailable
                ? "读取 ~/.dsh 会话缓存，可识别运行 / 完成 / 等待确认"
                : "未检测到 ~/.dsh 会话目录",
            category: .agent,
            available: dshAvailable,
            supported: dshAvailable
        ))

        // 4. 其他 AI CLI
        let runningMatches = Set(
            ProcessProbe.aiCLIProcesses(excluding: []).compactMap { ProcessProbe.match(for: $0)?.match }
        )
        let installedBinaries = CLIBinaryScanner.installedNames()

        for entry in ProcessProbe.knownCLI where !["claude", "codex"].contains(entry.match) {
            let running = runningMatches.contains(entry.match)
            let installed = installedBinaries.contains(entry.match)
            guard running || installed else { continue }
            result.append(DetectedAI(
                id: "cli:\(entry.match)",
                name: entry.provider,
                detail: running ? "检测到正在运行的命令行进程" : "检测到已安装的命令行工具",
                category: .cli,
                available: true,
                supported: true
            ))
        }

        // 5. 桌面应用（只做安装检测，避免造成“能监控任务”的误解）
        let appCandidates: [(String, String, String)] = [
            ("chatgpt", "ChatGPT", "/Applications/ChatGPT.app"),
            ("claude-app", "Claude", "/Applications/Claude.app"),
            ("cursor", "Cursor", "/Applications/Cursor.app"),
            ("windsurf", "Windsurf", "/Applications/Windsurf.app"),
            ("ollama-app", "Ollama", "/Applications/Ollama.app"),
        ]
        for (id, name, path) in appCandidates where FileManager.default.fileExists(atPath: path) {
            result.append(DetectedAI(
                id: "app:\(id)",
                name: name,
                detail: "桌面应用没有对外暴露任务状态，暂不支持任务级监控",
                category: .app,
                available: true,
                supported: false
            ))
        }

        return result.sorted { lhs, rhs in
            if lhs.supported != rhs.supported { return lhs.supported }
            if lhs.available != rhs.available { return lhs.available }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }
}

/// 在常见安装目录里找 AI CLI 可执行文件
enum CLIBinaryScanner {

    static func installedNames() -> Set<String> {
        let home = NSHomeDirectory()
        var directories = [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]

        // nvm 安装的全局包
        let nvmVersions = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersions) {
            directories += versions.map { "\(nvmVersions)/\($0)/bin" }
        }

        let manager = FileManager.default
        var names = Set<String>()
        for directory in directories {
            guard let contents = try? manager.contentsOfDirectory(atPath: directory) else { continue }
            for file in contents {
                names.insert(file.lowercased())
            }
        }
        return names
    }
}
