import Foundation

/// Хранение секретов (keyHex).
///
/// Раньше использовался Keychain с kSecAttrAccessGroup = "com.you.olcvpn".
/// Проблема: iOS требует, чтобы access group в запросах SecItem совпадала с
/// записью в entitlement `keychain-access-groups`, включая team-префикс
/// (`TEAMID.com.you.olcvpn`). Жёстко заданная строка без префикса приводила к
/// errSecMissingEntitlement (-34018): ключ не записывался и не читался, из-за
/// чего connect падал с «Выбери профиль и проверь ключ». На бесплатной подписи
/// keychain-sharing к тому же ненадёжен.
///
/// Решение: храним секреты в общем контейнере App Group (он уже используется
/// для профилей и стабильно работает и в app, и в extension). Это снимает
/// зависимость от team-префикса и keychain-access-groups.
///
/// Имя типа оставлено прежним (KeychainHelper), чтобы не трогать вызывающий код.
enum KeychainHelper {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: OLC.appGroup)
    }

    private static func storeKey(_ account: String) -> String {
        "olc.secret.\(account)"
    }

    static func set(_ value: String, account: String) {
        defaults?.set(value, forKey: storeKey(account))
    }

    static func get(account: String) -> String? {
        defaults?.string(forKey: storeKey(account))
    }

    static func delete(account: String) {
        defaults?.removeObject(forKey: storeKey(account))
    }
}
