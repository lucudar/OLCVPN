import AppIntents
import NetworkExtension

/// Подключение OLCVPN из Siri / приложения «Команды».
/// Использует последний сохранённый VPN-профиль (providerConfiguration уже записан
/// приложением при предыдущем подключении), поэтому работает без App Group.
struct ConnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Подключить OLCVPN"
    static var description = IntentDescription("Запускает последний настроенный VPN-туннель OLCVPN.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            throw VPNIntentError.notConfigured
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()
        return .result()
    }
}

/// Отключение OLCVPN из Siri / «Команд».
struct DisconnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Отключить OLCVPN"
    static var description = IntentDescription("Останавливает VPN-туннель OLCVPN.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else { return .result() }
        // Если включён режим «Всегда включён» (On-Demand) — выключаем, иначе система
        // тут же поднимет туннель заново.
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            try? await manager.saveToPreferences()
        }
        manager.connection.stopVPNTunnel()
        return .result()
    }
}

enum VPNIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notConfigured
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured:
            return "Сначала подключитесь вручную в приложении OLCVPN."
        }
    }
}

struct OLCAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectVPNIntent(),
                    phrases: ["Включи \(.applicationName)", "Подключи \(.applicationName)"],
                    shortTitle: "Подключить",
                    systemImageName: "bolt.fill")
        AppShortcut(intent: DisconnectVPNIntent(),
                    phrases: ["Выключи \(.applicationName)", "Отключи \(.applicationName)"],
                    shortTitle: "Отключить",
                    systemImageName: "power")
    }
}
