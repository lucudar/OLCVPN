import Foundation

/// Общие константы приложения и расширения.
enum OLC {
    /// App Group для обмена конфигом между app и extension.
    static let appGroup = "group.com.you.olcvpn"
    /// Keychain access group (включая Team ID-префикс задаётся в entitlements).
    static let keychainAccessGroup = "com.you.olcvpn"
    /// Bundle id расширения Packet Tunnel.
    static let tunnelBundleId = "com.you.olcvpn.OLCTunnel"
    /// Локальный SOCKS5-порт, который поднимает ядро olcRTC.
    static let socksPort = 10808
    /// Виртуальный адрес туннеля.
    static let tunnelIP = "10.8.0.2"
    static let tunnelMask = "255.255.255.0"
    static let defaultDNS = "8.8.8.8"
    /// Идентификатор клиента (peer id). Должен совпадать с серверным полем `data` — по умолчанию всегда "data".
    static let defaultClientID = "data"
}
