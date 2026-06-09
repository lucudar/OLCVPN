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
            let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = OLC.tunnelBundleId
            proto.serverAddress = "olcRTC"
            m.protocolConfiguration = proto
            m.localizedDescription = "OLCVPN"
            m.isEnabled = true
            try await m.saveToPreferences()
            try await m.loadFromPreferences()
            self.manager = m
            self.status = m.connection.status
            observeStatus()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func connect() {
        guard let manager else { lastError = "VPN не настроен"; return }
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
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
