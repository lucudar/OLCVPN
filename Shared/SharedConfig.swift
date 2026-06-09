import Foundation

/// Общее хранилище между app и extension.
/// Несекретные поля — в App Group UserDefaults, keyHex — в Keychain.
struct ActiveConfig: Codable {
    var carrier: String
    var roomID: String
    var clientID: String
    var transport: String
    var dns: String
    var socksPort: Int
    var keyHex: String
}

enum SharedConfig {
    private static let activeKey = "olc.active.profile"
    private static let keyAccount = "olc.active.keyHex"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: OLC.appGroup)
    }

    /// Сохранить активный профиль (вызывается из app перед connect).
    static func saveActive(profile: Profile, keyHex: String) {
        let payload: [String: Any] = [
            "carrier": profile.carrier.rawValue,
            "roomID": profile.roomID,
            "clientID": profile.clientID,
            "transport": profile.transport.rawValue,
            "dns": profile.dns,
            "socksPort": profile.socksPort
        ]
        defaults?.set(payload, forKey: activeKey)
        KeychainHelper.set(keyHex, account: keyAccount)
    }

    /// Прочитать активный конфиг (вызывается из extension).
    static func loadActive() -> ActiveConfig? {
        guard let dict = defaults?.dictionary(forKey: activeKey),
              let carrier = dict["carrier"] as? String,
              let roomID = dict["roomID"] as? String,
              let clientID = dict["clientID"] as? String,
              let transport = dict["transport"] as? String,
              let dns = dict["dns"] as? String,
              let socksPort = dict["socksPort"] as? Int,
              let keyHex = KeychainHelper.get(account: keyAccount)
        else { return nil }
        return ActiveConfig(carrier: carrier, roomID: roomID, clientID: clientID,
                            transport: transport, dns: dns, socksPort: socksPort, keyHex: keyHex)
    }
}
