import Foundation

/// Глобальные настройки приложения (App Group UserDefaults).
struct AppSettings: Codable, Equatable {
    var defaultDNS: String = OLC.defaultDNS + ":53"
    var defaultSocksPort: Int = OLC.socksPort
    var debugLogging: Bool = true
    /// Авто-переподключение: при неожиданном разрыве уже установленного
    /// соединения приложение само поднимает туннель заново (до 5 попыток).
    var autoReconnect: Bool = true
    /// Всегда включён (Kill Switch): системный On-Demand-профиль держит VPN
    /// поднятым и переподключает его автоматически. Отключается только вручную.
    var alwaysOn: Bool = false
}
