import Foundation

/// Простой журнал диагностики в общем контейнере App Group.
/// Пишут и приложение, и расширение; читает/экспортирует приложение.
enum DiagLog {
    private static let fileName = "olc.diag.log"
    private static let maxBytes = 256 * 1024

    /// Подробные/детальные логи (дамп конфигов, фазы Go-вызовов, парсинг URI и т.п.)
    /// пишутся только когда флаг поднят. Жизненный цикл и ошибки пишутся ВСЕГДА.
    /// Каждый процесс выставляет флаг самостоятельно: app — из AppSettings,
    /// extension — из cfg.debug (приходит через providerConfiguration).
    static var debugEnabled: Bool = true

    private static var fileURL: URL? {
        if let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: OLC.appGroup) {
            return group.appendingPathComponent(fileName)
        }
        // App Group недоступен (например, сертификат без группы) — пишем в
        // Documents текущего процесса, чтобы лог хотя бы сохранялся локально.
        if let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs.appendingPathComponent(fileName)
        }
        return nil
    }

    static func log(_ message: String, tag: String = "app") {
        let ts = ISO8601DateFormatter().string(from: Date())
        // Дублируем в системный журнал iOS. Его видно через idevicesyslog /
        // Console ДАЖЕ когда App Group недоступен (например при подписи ESign).
        // Фильтруй по префиксу OLCVPN.
        NSLog("%@", "[OLCVPN] [\(ts)] [\(tag)] \(message)")
        guard let url = fileURL else { return }
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

    /// Детальный лог: пишется только когда debugEnabled == true.
    /// Для дампа конфигов, фаз Go-вызовов, парсинга URI — того, что шумит.
    static func debug(_ message: String, tag: String = "app") {
        guard debugEnabled else { return }
        log(message, tag: tag)
    }

    /// Лог ошибки: пишется ВСЕГДА, отдельный тег «error» для быстрого поиска.
    static func error(_ message: String, tag: String = "error") {
        log(message, tag: tag)
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
