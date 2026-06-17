import Foundation

/// Транспорты olcRTC.
enum OLCTransport: String, Codable, CaseIterable, Identifiable {
    case vp8channel
    case datachannel
    case sei
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vp8channel: return "VP8 channel"
        case .datachannel: return "Data channel"
        case .sei:        return "SEI"
        }
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
    var transport: OLCTransport = .vp8channel
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
