import Foundation
import NetworkExtension
import Combine

/// Обёртка над NETunnelProviderManager: создание профиля, connect/disconnect, статус.
@MainActor
final class TunnelManager: ObservableObject {
    @Published var status: NEVPNStatus = .invalid
    @Published var lastError: String?
    /// Живой снимок in-memory лога расширения (через IPC). Также сохраняется в
    /// UserDefaults.standard (\"olc.ext.log\") и виден на экране диагностики.
    @Published var extensionLog: String = ""

    static let extLogKey = "olc.ext.log"

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var logPollTask: Task<Void, Never>?

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
            startLogPolling()
        } catch {
            self.lastError = error.localizedDescription
            DiagLog.log("connect ошибка: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        DiagLog.log("Запрос отключения")
    }

    // MARK: - Лог расширения по IPC (работает без App Group)

    /// Опрашиваем in-memory лог расширения ~25с (покрывает окно waitReady=15с),
    /// чтобы успеть забрать логи ДО того, как расширение умрёт при ошибке.
    func startLogPolling() {
        logPollTask?.cancel()
        logPollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<50 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                let dump = await self.fetchExtensionLog()
                if !dump.isEmpty {
                    self.extensionLog = dump
                    UserDefaults.standard.set(dump, forKey: TunnelManager.extLogKey)
                }
            }
        }
    }

    /// Запросить лог расширения по IPC. Работает, пока сессия connecting/connected.
    func fetchExtensionLog() async -> String {
        guard let session = manager?.connection as? NETunnelProviderSession else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            do {
                try session.sendProviderMessage(Data("getlog".utf8)) { resp in
                    let s = resp.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    cont.resume(returning: s)
                }
            } catch {
                cont.resume(returning: "")
            }
        }
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
