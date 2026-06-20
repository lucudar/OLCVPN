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
    /// Момент успешного подключения — для счётчика времени сессии. nil = не подключены.
    @Published var connectedSince: Date?
    /// Накопленный за сессию трафик (байты), приходит из расширения по IPC.
    @Published var txBytes: UInt64 = 0
    @Published var rxBytes: UInt64 = 0

    static let extLogKey = "olc.ext.log"

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var logPollTask: Task<Void, Never>?
    private var statsPollTask: Task<Void, Never>?
    /// Последнее значение lastError, которое мы уже залогировали, чтобы не
    /// спамить в лог на каждой смене статуса (наблюдатель срабатывает часто).
    private var lastLoggedError: String?

    // Состояние для авто-переподключения / on-demand.
    private var lastProviderConfig: [String: Any]?
    private var wantsConnection = false
    private var userInitiatedStop = false
    private var onDemandEnabled = false
    private var autoReconnectEnabled = false
    private var reconnectAttempts = 0

    func prepare() async {
        DiagLog.debug("prepare: loadAllFromPreferences…", tag: "tunnel")
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = all.first ?? NETunnelProviderManager()
            self.manager = m
            self.status = m.connection.status
            if m.connection.status == .connected { self.connectedSince = Date() }
            observeStatus()
            DiagLog.debug("prepare: готово, профилей VPN=\(all.count), статус=\(m.connection.status.rawValue)", tag: "tunnel")
        } catch {
            self.lastError = error.localizedDescription
            DiagLog.error("prepare ошибка: \(error.localizedDescription)")
        }
    }

    /// Подключение: записываем активный конфиг в providerConfiguration VPN-профиля
    /// (работает без App Group), сохраняем и стартуем.
    /// - onDemand: включить системный On-Demand (всегда включён / Kill Switch).
    /// - autoReconnect: переподключаться силами приложения при разрыве.
    func connect(providerConfig: [String: Any], onDemand: Bool = false, autoReconnect: Bool = false) {
        lastError = nil
        lastLoggedError = nil
        lastProviderConfig = providerConfig
        wantsConnection = true
        userInitiatedStop = false
        onDemandEnabled = onDemand
        autoReconnectEnabled = autoReconnect
        reconnectAttempts = 0
        DiagLog.debug("connect: старт (ключей=\(providerConfig.keys.count), onDemand=\(onDemand), autoReconnect=\(autoReconnect))", tag: "tunnel")
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
            applyOnDemand(to: m)
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

    /// Настраивает On-Demand-правила на профиле в соответствии с onDemandEnabled.
    private func applyOnDemand(to m: NETunnelProviderManager) {
        if onDemandEnabled {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            m.onDemandRules = [rule]
            m.isOnDemandEnabled = true
            DiagLog.log("On-Demand (всегда включён / Kill Switch) активирован")
        } else {
            m.onDemandRules = []
            m.isOnDemandEnabled = false
        }
    }

    /// Включить/выключить On-Demand на уже существующем профиле без переподключения.
    /// Применяется немедленно (если профиль уже настроен).
    func setOnDemand(_ enabled: Bool) {
        onDemandEnabled = enabled
        guard let m = manager, m.protocolConfiguration != nil else {
            DiagLog.debug("setOnDemand(\(enabled)): профиль ещё не настроен — применю при следующем подключении", tag: "tunnel")
            return
        }
        applyOnDemand(to: m)
        Task {
            do { try await m.saveToPreferences() }
            catch { DiagLog.error("setOnDemand: \(error.localizedDescription)") }
        }
    }

    func disconnect() {
        DiagLog.log("Запрос отключения")
        userInitiatedStop = true
        wantsConnection = false
        // Оптимистично показываем «Отключение…» СРАЗУ, не дожидаясь
        // NEVPNStatusDidChange. Иначе кнопка «висит», пока расширение гасит ядро
        // — отсюда ощущение большой задержки. Реальный статус придёт через наблюдателя.
        if status == .connected || status == .connecting || status == .reasserting {
            status = .disconnecting
        }
        logPollTask?.cancel()
        statsPollTask?.cancel()
        Task { await self.performStop() }
    }

    private func performStop() async {
        // Если включён On-Demand — сначала выключаем его, иначе система
        // немедленно переподключит туннель и «отключиться» не получится.
        if let m = manager, m.isOnDemandEnabled {
            m.isOnDemandEnabled = false
            m.onDemandRules = []
            do { try await m.saveToPreferences() }
            catch { DiagLog.error("performStop: не отключил on-demand: \(error.localizedDescription)") }
        }
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

    /// Пока сессия подключена — раз в 2с забираем счётчики трафика из расширения.
    func startStatsPolling() {
        statsPollTask?.cancel()
        statsPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let resp = await self.sendCommand("stats")
                if let parsed = TunnelManager.parseStats(resp) {
                    self.txBytes = parsed.tx
                    self.rxBytes = parsed.rx
                }
                if self.status != .connected { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Разбирает ответ расширения формата «tx=<байты>;rx=<байты>».
    static func parseStats(_ s: String) -> (tx: UInt64, rx: UInt64)? {
        var tx: UInt64?
        var rx: UInt64?
        for part in s.split(separator: ";") {
            let kv = part.split(separator: "=")
            guard kv.count == 2 else { continue }
            if kv[0] == "tx" { tx = UInt64(kv[1]) }
            if kv[0] == "rx" { rx = UInt64(kv[1]) }
        }
        if let tx, let rx { return (tx, rx) }
        return nil
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
                let prev = self.status
                self.status = conn.status
                DiagLog.log("статус -> \(self.statusText)")

                switch conn.status {
                case .connected:
                    if self.connectedSince == nil { self.connectedSince = Date() }
                    self.reconnectAttempts = 0
                    self.startStatsPolling()
                    // Сбрасываем «залипшую» ошибку при успешном подключении —
                    // иначе на экране ConnectView продолжала светиться старая.
                    if self.lastError != nil {
                        DiagLog.log("lastError сброшен (connected)")
                        self.lastError = nil
                        self.lastLoggedError = nil
                    }
                case .disconnected:
                    self.connectedSince = nil
                    self.txBytes = 0
                    self.rxBytes = 0
                    self.statsPollTask?.cancel()
                    self.maybeAutoReconnect(previous: prev)
                default:
                    break
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

    /// Авто-переподключение: только если соединение было установлено и неожиданно
    /// разорвалось (не пользователем и не в режиме On-Demand, который чинит себя сам).
    private func maybeAutoReconnect(previous: NEVPNStatus) {
        guard autoReconnectEnabled,
              wantsConnection,
              !userInitiatedStop,
              !onDemandEnabled,
              previous == .connected,
              let cfg = lastProviderConfig,
              reconnectAttempts < 5
        else { return }
        reconnectAttempts += 1
        let delay = min(2.0 * Double(reconnectAttempts), 10)
        DiagLog.log("Соединение разорвано — авто-переподключение через \(Int(delay)) с (попытка \(reconnectAttempts)/5)")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            if self.wantsConnection, !self.userInitiatedStop {
                await self.saveAndStart(providerConfig: cfg)
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

    /// Длительность текущей сессии (сек), либо nil если не подключены.
    var connectedDuration: TimeInterval? {
        guard let connectedSince else { return nil }
        return Date().timeIntervalSince(connectedSince)
    }

    var isConnected: Bool { status == .connected }
    var isBusy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }
}
