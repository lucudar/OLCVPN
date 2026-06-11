import Foundation

/// Глобальные настройки приложения (App Group UserDefaults).
struct AppSettings: Codable, Equatable {
    var defaultDNS: String = OLC.defaultDNS + ":53"
    var defaultSocksPort: Int = OLC.socksPort
    var debugLogging: Bool = true
}
