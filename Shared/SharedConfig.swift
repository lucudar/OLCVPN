import Foundation

/// Общее хранилище между app и extension.
///
/// Конфиг доставляется в extension ДВУМЯ путями (extension берёт первый доступный):
///   1) через `providerConfiguration` VPN-профиля — НЕ требует App Group и работает
///      даже на сертификатах, которые не разрешают группу `group.com.you.olcvpn`;
///   2) через App Group UserDefaults — как резерв, если providerConfiguration пуст.
struct ActiveConfig: Codable {
    var carrier: String
    var roomID: String
    var clientID: String
    var transport: String
    var dns: String
    var socksPort: Int
    var keyHex: String
    var debug: Bool
}

enum SharedConfig {
    private static let activeKey = "olc.active.profile"
    private static let keyAccount = "olc.active.keyHex"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: OLC.appGroup)
    }

    // MARK: - providerConfiguration (основной путь, без App Group)

    /// Собирает словарь для `NETunnelProviderProtocol.providerConfiguration`.
    /// Все значения plist-сериализуемы (String/Int/Bool).
    static func providerConfig(profile: Profile, keyHex: String, debug: Bool) -> [String: Any] {
        [
            "carrier": profile.carrier.rawValue,
            "roomID": profile.roomID,
            "clientID": profile.clientID.isEmpty ? OLC.defaultClientID : profile.clientID,
            "transport": profile.transport.rawValue,
            "dns": profile.dns,
            "socksPort": profile.socksPort,
            "keyHex": keyHex,
            "debug": debug
        ]
    }

    /// Читает конфиг из providerConfiguration (вызывается из extension первым делом).
    static func fromProviderConfig(_ dict: [String: Any]?) -> ActiveConfig? {
        guard let dict = dict,
              let carrier = dict["carrier"] as? String,
              let roomID = dict["roomID"] as? String,
              let transport = dict["transport"] as? String,
              let dns = dict["dns"] as? String,
              let socksPort = (dict["socksPort"] as? Int) ?? (dict["socksPort"] as? NSNumber)?.intValue,
              let keyHex = dict["keyHex"] as? String, !keyHex.isEmpty
        else { return nil }
        let rawClientID = (dict["clientID"] as? String) ?? ""
        let clientID = rawClientID.isEmpty ? OLC.defaultClientID : rawClientID
        let debug = (dict["debug"] as? Bool) ?? true
        return ActiveConfig(carrier: carrier, roomID: roomID, clientID: clientID,
                            transport: transport, dns: dns, socksPort: socksPort,
                            keyHex: keyHex, debug: debug)
    }

    // MARK: - App Group (резервный путь)

    /// Сохранить активный профиль (вызывается из app перед connect).
    static func saveActive(profile: Profile, keyHex: String, debug: Bool = true) {
        let payload: [String: Any] = [
            "carrier": profile.carrier.rawValue,
            "roomID": profile.roomID,
            "clientID": profile.clientID.isEmpty ? OLC.defaultClientID : profile.clientID,
            "transport": profile.transport.rawValue,
            "dns": profile.dns,
            "socksPort": profile.socksPort,
            "debug": debug
        ]
        defaults?.set(payload, forKey: activeKey)
        KeychainHelper.set(keyHex, account: keyAccount)
    }

    /// Прочитать активный конфиг из App Group (резерв, если providerConfiguration пуст).
    static func loadActive() -> ActiveConfig? {
        guard let dict = defaults?.dictionary(forKey: activeKey),
              let carrier = dict["carrier"] as? String,
              let roomID = dict["roomID"] as? String,
              let transport = dict["transport"] as? String,
              let dns = dict["dns"] as? String,
              let socksPort = dict["socksPort"] as? Int,
              let keyHex = KeychainHelper.get(account: keyAccount)
        else { return nil }
        let rawClientID = (dict["clientID"] as? String) ?? ""
        let clientID = rawClientID.isEmpty ? OLC.defaultClientID : rawClientID
        let debug = (dict["debug"] as? Bool) ?? true
        return ActiveConfig(carrier: carrier, roomID: roomID, clientID: clientID,
                            transport: transport, dns: dns, socksPort: socksPort,
                            keyHex: keyHex, debug: debug)
    }
}
