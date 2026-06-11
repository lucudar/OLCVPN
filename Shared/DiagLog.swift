import Foundation

/// Простой журнал диагностики в общем контейнере App Group.
/// Пишут и приложение, и расширение; читает/экспортирует приложение.
enum DiagLog {
    private static let fileName = "olc.diag.log"
    private static let maxBytes = 256 * 1024

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: OLC.appGroup)?
            .appendingPathComponent(fileName)
    }

    static func log(_ message: String, tag: String = "app") {
        guard let url = fileURL else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(tag)] \(message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        trimIfNeeded()
    }

    static func read() -> String {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? Data().write(to: url)
    }

    private static func trimIfNeeded() {
        guard let url = fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        let trimmed = data.suffix(maxBytes / 2)
        try? trimmed.write(to: url)
    }
}
