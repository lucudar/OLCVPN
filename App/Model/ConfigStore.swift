import Foundation
import Combine

/// Хранилище списка профилей (в App Group). Ключи — в Keychain по profile.id.
final class ConfigStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?

    private let listKey = "olc.profiles.list"
    private let activeIDKey = "olc.profiles.activeID"
    private var defaults: UserDefaults? { UserDefaults(suiteName: OLC.appGroup) }

    init() { load() }

    func load() {
        if let data = defaults?.data(forKey: listKey),
           let list = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = list
        }
        if let s = defaults?.string(forKey: activeIDKey) { activeProfileID = UUID(uuidString: s) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults?.set(data, forKey: listKey)
        }
        defaults?.set(activeProfileID?.uuidString, forKey: activeIDKey)
    }

    func keyHex(for profile: Profile) -> String? {
        KeychainHelper.get(account: "olc.key.\(profile.id.uuidString)")
    }

    func add(profile: Profile, keyHex: String) {
        profiles.append(profile)
        KeychainHelper.set(keyHex, account: "olc.key.\(profile.id.uuidString)")
        if activeProfileID == nil { activeProfileID = profile.id }
        persist()
    }

    func update(profile: Profile, keyHex: String?) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        }
        if let keyHex { KeychainHelper.set(keyHex, account: "olc.key.\(profile.id.uuidString)") }
        persist()
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        KeychainHelper.delete(account: "olc.key.\(profile.id.uuidString)")
        if activeProfileID == profile.id { activeProfileID = profiles.first?.id }
        persist()
    }

    func setActive(_ profile: Profile) {
        activeProfileID = profile.id
        persist()
    }

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Переносит активный профиль + ключ в SharedConfig для extension.
    func publishActiveToTunnel() -> Bool {
        guard let p = activeProfile, let key = keyHex(for: p) else { return false }
        SharedConfig.saveActive(profile: p, keyHex: key)
        return true
    }
}
