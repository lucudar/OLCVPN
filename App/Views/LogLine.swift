import SwiftUI

/// Разобранная строка лога для удобного отображения в `LogView`.
///
/// Понимает оба формата, которые пишет приложение:
///   - `[2026-06-18T21:34:00Z] [tag] сообщение`  — DiagLog / лог расширения;
///   - `[21:34:00] сообщение` и `[core] сообщение` — лог прокси-режима;
///   - `=== Заголовок ===`                         — разделители секций.
///
/// Лежит в App/Views (а не App/Model), т.к. зависит от UI-палитры `Theme`,
/// которая не входит в исходники тест-таргета.
struct LogLine: Identifiable {
    let id: Int
    let time: String?       // компактное HH:mm:ss(.SSS)
    let tag: String?
    let category: Category
    let message: String
    let raw: String

    enum Category {
        case error, core, tunnel, ping, config, uri, section, app

        var color: Color {
            switch self {
            case .error:   return Theme.statusError
            case .core:    return Theme.teal
            case .tunnel:  return Theme.blue
            case .ping:    return Theme.indigo
            case .config:  return Theme.textSecondary
            case .uri:     return Theme.green
            case .section: return Theme.green
            case .app:     return Theme.textPrimary
            }
        }
    }

    // MARK: - Фильтры (чипы)

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Все"
        case errors = "Ошибки"
        case core = "Core"
        case app = "Приложение"
        var id: String { rawValue }

        func matches(_ line: LogLine) -> Bool {
            switch self {
            case .all:    return true
            case .errors: return line.category == .error
            case .core:   return line.category == .core
            case .app:    return line.category != .core   // всё, кроме внутренних логов ядра
            }
        }
    }

    // MARK: - Парсинг

    static func parse(_ raw: String, id: Int) -> LogLine {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("===") {
            return LogLine(id: id, time: nil, tag: nil, category: .section,
                           message: trimmed.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces),
                           raw: raw)
        }

        // Снимаем ведущие [...] группы.
        var rest = Substring(trimmed)
        var brackets: [String] = []
        while rest.first == "[", let close = rest.firstIndex(of: "]") {
            brackets.append(String(rest[rest.index(after: rest.startIndex)..<close]))
            rest = rest[rest.index(after: close)...].drop(while: { $0 == " " })
            if brackets.count >= 2 { break }   // максимум [time] [tag]
        }

        var time: String? = nil
        var tag: String? = nil
        for b in brackets {
            if time == nil, let t = compactTime(b) { time = t }
            else if tag == nil { tag = b }
        }

        let message = String(rest)
        let category = categorize(tag: tag, message: message)
        return LogLine(id: id, time: time, tag: tag, category: category, message: message, raw: raw)
    }

    /// Преобразует ISO8601 / `HH:mm:ss` в компактное время или возвращает nil,
    /// если строка не похожа на время (значит, это tag).
    private static func compactTime(_ s: String) -> String? {
        if let tIdx = s.firstIndex(of: "T") {
            // ISO8601: ...THH:mm:ss(.SSS)(Z|+hh:mm)
            var t = s[s.index(after: tIdx)...]
            if let zEnd = t.firstIndex(where: { $0 == "Z" || $0 == "+" }) {
                t = t[..<zEnd]
            }
            return String(t)
        }
        // Голое HH:mm:ss
        let parts = s.split(separator: ":")
        if parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return s
        }
        return nil
    }

    private static func categorize(tag: String?, message: String) -> Category {
        switch tag {
        case "error":            return .error
        case "core":             return .core
        case "tunnel", "tun2socks": return .tunnel
        case "ping":             return .ping
        case "config", "store":  return .config
        case "uri":              return .uri
        default: break
        }
        let lower = message.lowercased()
        if lower.contains("ошибка") || lower.contains("error") || lower.contains("failed")
            || lower.contains("отказ") || message.contains("❌") {
            return .error
        }
        return .app
    }
}

extension Array where Element == LogLine {
    /// Разбирает многострочный текст лога в массив `LogLine`.
    static func from(text: String) -> [LogLine] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { LogLine.parse(String($0.element), id: $0.offset) }
    }
}
