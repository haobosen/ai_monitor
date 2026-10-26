import AppKit
import Foundation

let arguments = CommandLine.arguments

// MARK: - 开发调试：重置 / 预置初始化状态

if arguments.contains("--reset-config") {
    let defaults = UserDefaults.standard
    ["enabledProviders", "hasOnboarded", "notificationsMuted", "panelFrame"].forEach {
        defaults.removeObject(forKey: $0)
    }
    defaults.synchronize()
    print("已重置配置")
}

if arguments.contains("--mark-onboarded") {
    UserDefaults.standard.set(true, forKey: "hasOnboarded")
    UserDefaults.standard.synchronize()
}

// MARK: - 调试 / 校验入口

if arguments.contains("--discover") {
    let providers = AIProviderCatalog.discover()
    let payload: [[String: Any]] = providers.map { ai in
        [
            "id": ai.id,
            "name": ai.name,
            "detail": ai.detail,
            "available": ai.available,
            "supported": ai.supported,
            "category": ai.categoryLabel,
        ]
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if arguments.contains("--dump") {
    let tasks = MonitorEngine.scanAll()
    let formatter = ISO8601DateFormatter()
    let payload: [[String: Any]] = tasks.map { task in
        var dict: [String: Any] = [
            "id": task.id,
            "provider": task.provider,
            "title": task.title,
            "project": task.project,
            "status": task.status.rawValue,
            "statusLabel": task.status.label,
            "detail": task.detail,
            "updatedAt": formatter.string(from: task.updatedAt),
            "historical": task.isHistorical,
        ]
        if let pid = task.pid { dict["pid"] = pid }
        if let source = task.sourcePath { dict["source"] = source }
        return dict
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

// MARK: - 单实例

if let bundleID = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .first(where: { $0.processIdentifier != getpid() }) {
    if #available(macOS 14.0, *) {
        existing.activate()
    } else {
        existing.activate(options: [.activateIgnoringOtherApps])
    }
    exit(0)
}

// MARK: - 正常启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
