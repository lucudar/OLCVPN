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
    /// Последнее значение lastError, которое мы уже залогировали, чтобы не
    /// спамить в лог на каждой смене статуса (наблюдатель срабатывает часто).
    private var lastLoggedError: String?

    func prepare() async {
        DiagLog.debug("prepare: loadAllFromPreferences…", tag: "tunnel")
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = all.first ?? NETunnelProviderManager()
            self.manager = m
            self.status = m.connection.status
            observeStatus()
            DiagLog.debug("prepare: готово, профилей VPN=\(all.count), статус=\(m.connection.status.rawValue)", tag: "tunnel")
        } catch {
            self.lastError = error.localizedDescription
            DiagLog.error("prepare ошибка: \(error.localizedDescription)")
        }
    }

    /// Подключение: записываем активный конфиг в providerConfiguration VPN-профиля
    /// (работает без App Group), сохраняем и стартуем.
    func connect(providerConfig: [String: Any]) {
        lastError = nil
        lastLoggedError = nil
        DiagLog.debug("connect: старт (ключей в providerConfig: \(providerConfig.keys.count))", tag: "tunnel")
        Task { await self.saveAndStart(providerConfig: providerConfig) }
    }

    private func saveAndStart(providerConfig: [String: Any]) async {
        do {
            DiagLog.debug("saveAndStart: loadAllFromPreferences…", tag: "tunnel")
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = manager ?? all.first ?? NETunnelProviderManager()
            let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = OLC.tunnelBundleId
            proto.serverAddress = "olcRTC"
            proto.providerConfiguration = providerConfig
            m.protocolConfiguration = proto
            m.localizedDescription = "OLCVPN"
            m.isEnabled = true
            DiagLog.debug("saveAndStart: saveToPreferences…", tag: "tunnel")
            try await m.saveToPreferences()
            DiagLog.debug("saveAndStart: loadFromPreferences…", tag: "tunnel")
            try await m.loadFromPreferences()
            self.manager = m
            observeStatus()
            DiagLog.debug("saveAndStart: startVPNTunnel…", tag: "tunnel")
            try m.connection.startVPNTunnel()
            DiagLog.log("Запрос подключения отправлен (providerConfiguration)")
            startLogPolling()
        } catch {
            self.lastError = error.localizedDescription
            DiagLog.error("connect/saveAndStart ошибка: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        DiagLog.log("Запрос отключения")
        // Оптимистично показываем «Отключение…» СРАЗУ, не дожидаясь
        // NEVPNStatusDidChange. Иначе кнопка «висит», пока расширение гасит ядро
        // — отсюда ощущение большой задержки. Реальный статус придёт через наблюдателя.
        if status == .connected || status == .connecting || status == .reasserting {
            status = .disconnecting
        }
        logPollTask?.cancel()
        manager?.connection.stopVPNTunnel()
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
        await sendCommand("getlog")
    }

    /// Отправить произвольную команду расширению по IPC и вернуть ответ строкой.
    /// Работает, пока сессия connecting/connected (App Group не требуется).
    func sendCommand(_ cmd: String) async -> String {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            DiagLog.debug("IPC '\(cmd)': нет активной сессии", tag: "tunnel")
            return ""
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            do {
                DiagLog.debug("IPC '\(cmd)' → extension…", tag: "tunnel")
                try session.sendProviderMessage(Data(cmd.utf8)) { resp in
                    let s = resp.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    DiagLog.debug("IPC '\(cmd)' ← \(s.isEmpty ? "пусто" : "\(s.count) байт")", tag: "tunnel")
                    cont.resume(returning: s)
                }
            } catch {
                DiagLog.error("IPC '\(cmd)' ошибка: \(error.localizedDescription)")
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
            Task { @MainActor in
                self.status = conn.status
                DiagLog.log("статус -> \(self.statusText)")
                // Сбрасываем «залипшую» ошибку при успешном подключении —
                // иначе на экране ConnectView продолжала светиться старая.
                if conn.status == .connected, self.lastError != nil {
                    DiagLog.log("lastError сброшен (connected)")
                    self.lastError = nil
                    self.lastLoggedError = nil
                }
                // Логируем ошибку только если она изменилась с прошлого раза:
                // наблюдатель NEVPNStatusDidChange срабатывает на каждое
                // промежуточное состояние и плодил бы дубли.
                if let e = self.lastError, !e.isEmpty, e != self.lastLoggedError {
                    DiagLog.error("lastError: \(e)")
                    self.lastLoggedError = e
                }
            }
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
