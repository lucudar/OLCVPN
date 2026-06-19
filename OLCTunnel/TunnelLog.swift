import Foundation

/// In-memory журнал расширения.
///
/// Зачем отдельно от DiagLog: на некоторых сертификатах (например, подпись через
/// ESign без разрешённой App Group) контейнер `group.com.you.olcvpn` недоступен,
/// и DiagLog молча теряет записи. Этот буфер живёт в памяти процесса расширения и
/// отдаётся приложению по IPC (`handleAppMessage` -> "getlog"), что работает БЕЗ
/// App Group, пока сессия туннеля жива. Дополнительно зеркалим в DiagLog — если
/// App Group всё-таки доступен, лог переживёт перезапуск.
final class TunnelLog {
    static let shared = TunnelLog()

    private let queue = DispatchQueue(label: "olc.tunnellog")
    private var lines: [String] = []
    private let maxLines = 2000
    /// Статический потокобезопасный ISO-форматтер (формирование строки даты у
    /// ISO8601DateFormatter потокобезопасно), один на процесс.
    private static let iso = ISO8601DateFormatter()

    func log(_ message: String, tag: String = "tunnel") {
        let line = "[\(TunnelLog.iso.string(from: Date()))] [\(tag)] \(message)"
        queue.sync {
            lines.append(line)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        }
        // Зеркалим в App Group (best-effort).
        DiagLog.log(message, tag: tag)
    }

    func dump() -> String {
        queue.sync { lines.joined(separator: "\n") }
    }

    func clear() {
        queue.sync { lines.removeAll() }
    }
}
