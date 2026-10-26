import Foundation

/// 轻量日志，方便排查（~/Library/Logs/AIMonitor.log）
enum Log {
    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/AIMonitor.log")

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let queue = DispatchQueue(label: "com.haobosen.aimonitor.log")

    static func write(_ message: String) {
        queue.async {
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let manager = FileManager.default

            if !manager.fileExists(atPath: url.path) {
                try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
                return
            }

            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
               size.intValue > 2 * 1024 * 1024 {
                try? manager.removeItem(at: url)
                try? data.write(to: url)
                return
            }

            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
}
