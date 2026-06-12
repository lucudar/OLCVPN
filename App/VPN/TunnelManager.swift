import Foundation
import NetworkExtension
import Combine

/// Обёртка над NETunnelProviderManager: создание профиля, connect/disconnect, статус.
@MainActor
final class TunnelManager: ObservableObject {
    @Published var status: NEVPNStatus = .invalid
    @Published var lastError: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    func prepare() async {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = all.first ?? NETunnelProviderManager()
            self.manager = m
            self.status = m.connection.status
            observeStatus()
        } catch {
            self.lastError = error.localizedDescription
            DiagLog.log("prepare ошибка: \(error.localizedDescription)")
        }
    }

    /// Подключение: записываем активный конфиг в providerConfiguration VPN-профиля
    /// (работает без App Group), сохраняем и стартуем.
    func connect(providerConfig: [String: Any]) {
        lastError = nil
        Task { await self.saveAndStart(providerConfig: providerConfig) }
    }

    private func saveAndStart(providerConfig: [String: Any]) async {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = manager ?? all.first ?? NETunnelProviderManager()
            let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = OLC.tunnelBundleId
            proto.serverAddress = "olcRTC"
            proto.providerConfiguration = providerConfig
            m.protocolConfiguration = proto
            m.localizedDescription = "OLCVPN"
            m.isEnabled = true
            try await m.saveToPreferences()
            try await m.loadFromPreferences()
            self.manager = m
            observeStatus()
            try m.connection.startVPNTunnel()
            DiagLog.log("Запрос подключения (providerConfiguration)")
        } catch {
            self.lastError = error.localizedDescription
            DiagLog.log("connect ошибка: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        DiagLog.log("Запрос отключения")
    }

    private func observeStatus() {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager?.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self, let conn = self.manager?.connection else { return }
            Task { @MainActor in self.status = conn.status }
        }
    }

    var statusText: String {
        switch status {
        case .invalid: return "Не настроен"
        case .disconnected: return "Отключено"
        case .connecting: return "Подключение…"
        case .connected: return "Подключено"
        case .reasserting: return "Переподключение…"
        case .disconnecting: return "Отключение…"
        @unknown default: return "—"
        }
    }

    var isConnected: Bool { status == .connected }
    var isBusy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }
}
