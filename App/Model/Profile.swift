import Foundation

/// Транспорты olcRTC. rawValue ДОЛЖЕН совпадать с тем, что понимает ядро
/// (`MobileSetTransport`) и парсер `olcrtc://` — отсюда `seichannel`, а не `sei`.
enum OLCTransport: String, Codable, CaseIterable, Identifiable {
    case datachannel
    case vp8channel
    case seichannel
    case videochannel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .datachannel:  return "Data channel"
        case .vp8channel:   return "VP8 channel"
        case .seichannel:   return "SEI channel"
        case .videochannel: return "Video channel"
        }
    }

    /// Лояльный декод: старое значение `"sei"` маппим в `.seichannel`, любое
    /// другое неизвестное — в `.datachannel`, чтобы один битый профиль не
    /// ронял декод всего списка `[Profile]` (иначе экран профилей пустеет).
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        switch raw.lowercased() {
        case "sei", "seichannel": self = .seichannel
        case "vp8channel":        self = .vp8channel
        case "videochannel":      self = .videochannel
        case "datachannel":       self = .datachannel
        default:                  self = .datachannel
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Auth-провайдеры (carrier).
enum OLCCarrier: String, Codable, CaseIterable, Identifiable {
    case jitsi
    case telemost
    case wbstream
    var id: String { rawValue }
}

/// Ключи параметров транспорта в payload olcrtc:// (<k=v&k=v>).
enum OLCTransportParam {
    static let vp8FPS = "vp8-fps"
    static let vp8Batch = "vp8-batch"
}

/// Профиль подключения. `keyHex` хранится НЕ здесь, а в Keychain (по id).
struct Profile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var carrier: OLCCarrier
    var roomID: String
    var clientID: String
    var transport: OLCTransport = .datachannel
    var dns: String = OLC.defaultDNS + ":53"
    var socksPort: Int = OLC.socksPort
    /// Необязательные параметры транспорта из olcrtc:// payload (vp8-fps и т.п.).
    var transportParams: [String: String] = [:]
    /// Комментарий из MIMO-поля olcrtc://.
    var note: String = ""
    /// Белый список: домены/IP/CIDR, которые идут напрямую (минуя VPN-туннель).
    var whitelist: [String] = []

    static func == (lhs: Profile, rhs: Profile) -> Bool { lhs.id == rhs.id }
}
