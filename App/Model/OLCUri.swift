import Foundation

/// Парсер/сборщик компактного формата olcrtc:// (клиентское соглашение).
///
///   olcrtc://<Auth>?<Transport>@<RoomID>#<EncryptionKey>$<MIMO>
///   olcrtc://<Auth>?<Transport><key=value&key=value>@<RoomID>#<EncryptionKey>$<MIMO>
///
/// Блок <...> после имени транспорта — payload параметров, опционален.
enum OLCUri {
    enum ParseError: Error, Equatable {
        case missingScheme
        case missingAuth
        case missingTransport
        case missingRoom
        case missingKey
        case invalidKey
        case unknownCarrier(String)
        case unknownTransport(String)
    }

    static let scheme = "olcrtc://"

    /// Разбирает строку в (Profile, keyHex).
    ///
    /// Логирует: вход (первые символы строки, без секрета), результат и — при
    /// провале — какая именно часть URI не прошла. Полный ключ в лог не пишем.
    static func parse(_ raw: String) throws -> (profile: Profile, keyHex: String) {
        // Обрезаем показ до первого '#' (секрета) — достаточно для диагностики.
        let preview: String = {
            if let h = raw.firstIndex(of: "#") { return String(raw[..<h]) }
            return raw
        }()
        DiagLog.debug("parse olcrtc://: \(preview)…", tag: "uri")
        do {
            let result = try parseRaw(raw)
            DiagLog.debug("parse OK: carrier=\(result.profile.carrier.rawValue) transport=\(result.profile.transport.rawValue) room=\(result.profile.roomID) keyLen=\(result.keyHex.count)", tag: "uri")
            return result
        } catch let e as ParseError {
            DiagLog.error("parse olcrtc://: \(describe(e)) [вход: \(preview)…]", tag: "uri")
            throw e
        }
    }

    private static func parseRaw(_ raw: String) throws -> (profile: Profile, keyHex: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.lowercased().hasPrefix(scheme) else { throw ParseError.missingScheme }
        s.removeFirst(scheme.count)

        // 1) MIMO после '$'
        var note = ""
        if let dollar = s.firstIndex(of: "$") {
            note = String(s[s.index(after: dollar)...])
            s = String(s[..<dollar])
        }

        // 2) key после '#'
        guard let hash = s.firstIndex(of: "#") else { throw ParseError.missingKey }
        let keyHex = String(s[s.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
        s = String(s[..<hash])
        guard isValidKeyHex(keyHex) else { throw ParseError.invalidKey }

        // 3) room после '@'
        guard let at = s.firstIndex(of: "@") else { throw ParseError.missingRoom }
        let roomID = String(s[s.index(after: at)...])
        s = String(s[..<at])
        guard !roomID.isEmpty else { throw ParseError.missingRoom }

        // 4) auth до '?'
        guard let q = s.firstIndex(of: "?") else { throw ParseError.missingTransport }
        let authStr = String(s[..<q]).lowercased()
        guard !authStr.isEmpty else { throw ParseError.missingAuth }
        guard let carrier = OLCCarrier(rawValue: authStr) else {
            throw ParseError.unknownCarrier(authStr)
        }

        // 5) transport (+ optional <payload>)
        var transportPart = String(s[s.index(after: q)...])
        var params: [String: String] = [:]
        if let lt = transportPart.firstIndex(of: "<"),
           let gt = transportPart.firstIndex(of: ">") {
            let payload = String(transportPart[transportPart.index(after: lt)..<gt])
            params = parsePayload(payload)
            transportPart = String(transportPart[..<lt])
        }
        let transportName = transportPart.lowercased()
        guard !transportName.isEmpty else { throw ParseError.missingTransport }
        guard let transport = OLCTransport(rawValue: transportName) else {
            throw ParseError.unknownTransport(transportName)
        }

        var profile = Profile(
            name: note.isEmpty ? "\(carrier.rawValue)/\(transport.rawValue)" : note,
            carrier: carrier,
            roomID: roomID,
            clientID: OLC.defaultClientID,
            transport: transport
        )
        profile.transportParams = params
        profile.note = note
        return (profile, keyHex)
    }

    /// Собирает строку olcrtc:// из профиля и ключа (обратная операция к parse).
    static func serialize(profile: Profile, keyHex: String) -> String {
        var payload = ""
        if !profile.transportParams.isEmpty {
            let pairs = profile.transportParams
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            payload = "<\(pairs)>"
        }
        var s = "\(scheme)\(profile.carrier.rawValue)?\(profile.transport.rawValue)\(payload)@\(profile.roomID)#\(keyHex)"
        let mimo = profile.note.isEmpty ? profile.name : profile.note
        if !mimo.isEmpty { s += "$\(mimo)" }
        DiagLog.debug("serialize: carrier=\(profile.carrier.rawValue) transport=\(profile.transport.rawValue) room=\(profile.roomID) keyLen=\(keyHex.count)", tag: "uri")
        return s
    }

    /// Человекочитаемое описание ошибки парсинга (для лога и UI).
    private static func describe(_ error: ParseError) -> String {
        switch error {
        case .missingScheme:        return "нет префикса olcrtc://"
        case .missingAuth:          return "нет carrier (jitsi/telemost/wbstream)"
        case .missingTransport:     return "нет транспорта"
        case .missingRoom:          return "нет roomID (после @)"
        case .missingKey:           return "нет ключа (после #)"
        case .invalidKey:           return "ключ не 64 hex"
        case .unknownCarrier(let c):  return "неизвестный carrier: \(c)"
        case .unknownTransport(let t): return "неизвестный транспорт: \(t)"
        }
    }

    static func isValidKeyHex(_ key: String) -> Bool {
        guard key.count == 64 else { return false }
        return key.allSatisfy { $0.isHexDigit }
    }

    private static func parsePayload(_ payload: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in payload.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }
}
