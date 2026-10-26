import Foundation

/// JSONL / 大文件尾部读取工具
enum FileTail {

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    /// 读取文件末尾约 maxBytes 字节，按行切分（丢弃可能被截断的首行）
    static func tailLines(at url: URL, maxBytes: Int = 512 * 1024) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = fileSize(url)
        let start = max(0, size - maxBytes)
        do {
            try handle.seek(toOffset: UInt64(start))
        } catch {
            return []
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).map { Data($0) }
        if start > 0, !lines.isEmpty {
            lines.removeFirst() // 首行大概率被截断
        }
        return lines
    }

    static func headLines(at url: URL, maxBytes: Int = 256 * 1024) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return [] }
        return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).map { Data($0) }
    }

    static func jsonObjects(in lines: [Data]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            result.append(object)
        }
        return result
    }

    static func tailObjects(at url: URL, maxBytes: Int = 512 * 1024) -> [[String: Any]] {
        jsonObjects(in: tailLines(at: url, maxBytes: maxBytes))
    }

    static func headObjects(at url: URL, maxBytes: Int = 256 * 1024) -> [[String: Any]] {
        jsonObjects(in: headLines(at: url, maxBytes: maxBytes))
    }

    static func date(from value: Any?) -> Date? {
        if let number = value as? Double {
            // 毫秒时间戳
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        if let number = value as? Int {
            let double = Double(number)
            return Date(timeIntervalSince1970: double > 10_000_000_000 ? double / 1000 : double)
        }
        guard let string = value as? String else { return nil }
        return isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func strings(in directory: URL, extension ext: String, modifiedWithin seconds: TimeInterval) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-seconds)
        var result: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == ext else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }
            result.append(url)
        }
        return result
    }
}
