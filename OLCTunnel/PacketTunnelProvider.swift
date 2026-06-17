import NetworkExtension

/// Основной класс расширения VPN-туннеля.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var tun2socks: Tun2Socks?

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let t0 = Date()
        TunnelLog.shared.clear()
        TunnelLog.shared.log("=== startTunnel вызван ===")

        // Конфиг берём СНАЧАЛА из providerConfiguration (не требует App Group),
        // и только потом — из App Group как резерв.
        let providerConf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        let keys = providerConf?.keys.sorted().joined(separator: ",") ?? "nil"
        TunnelLog.shared.log("providerConfiguration ключи: \(keys)")

        let source: String
        let maybeCfg: ActiveConfig?
        if let c = SharedConfig.fromProviderConfig(providerConf) {
            maybeCfg = c
            source = "providerConfiguration"
        } else {
            TunnelLog.shared.log("providerConfiguration не распарсился — пробую App Group")
            maybeCfg = SharedConfig.loadActive()
            source = "appGroup"
        }

        guard let cfg = maybeCfg else {
            TunnelLog.shared.log("ОШИБКА: нет активного конфига (providerConfiguration пуст, App Group недоступен)")
            completionHandler(NSError(domain: "olc", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Нет активного профиля"]))
            return
        }

        TunnelLog.shared.log("Конфиг [\(source)]: carrier=\(cfg.carrier) transport=\(cfg.transport) room=\(cfg.roomID) clientID='\(cfg.clientID)' dns=\(cfg.dns) socksPort=\(cfg.socksPort) keyLen=\(cfg.keyHex.count) debugProfile=\(cfg.debug)")

        // Подробность логов ядра/конфига в extension задаётся полем debug
        // конфига (приходит через providerConfiguration из настроек приложения).
        DiagLog.debugEnabled = cfg.debug

        // Старт ядра — в ФОНОВОМ потоке, чтобы очередь расширения оставалась
        // отзывчивой (иначе handleAppMessage/IPC не отвечает, пока висит waitReady).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 0) Подключаем capture логов ядра olcRTC ДО старта, иначе
            // ранние строки [pc]/[ice]/jitsi/smux (в т.ч. ошибки инициализации)
            // уйдут в stderr, который iOS у extension не показывает, и мы их
            // потеряем. Ядро пишет лог двумя путями:
            //   - Go-пакет `log` -> SetLogWriter -> CoreLogWriter (основной канал);
            //   - прямой вывод в stderr (fmt.Print и пр.) -> CoreLogCapture.
            // Зеркалим оба в TunnelLog, чтобы видеть в IPC-дампе и в DiagnosticsView.
            CoreLogCapture.start { line in
                TunnelLog.shared.log(line, tag: "core")
            }
            OLCCore.setLogWriter(CoreLogWriter { line in
                TunnelLog.shared.log(line, tag: "core")
            })
            TunnelLog.shared.log("Capture логов ядра подключен (stderr + log.SetOutput)")

            // 1) Настройка ядра olcRTC. На время диагностики всегда debug=true.
            OLCCore.setProviders()
            OLCCore.setTransport(cfg.transport)
            OLCCore.setDNS(cfg.dns)
            OLCCore.setDebug(true)
            TunnelLog.shared.log("Ядро сконфигурировано (transport=\(cfg.transport), dns=\(cfg.dns), debug=true)")

            // 2) Запуск SOCKS5 ядра
            do {
                let s1 = Date()
                TunnelLog.shared.log("MobileStart…")
                try OLCCore.start(carrier: cfg.carrier, roomID: cfg.roomID,
                                  clientID: cfg.clientID, keyHex: cfg.keyHex,
                                  socksPort: cfg.socksPort)
                TunnelLog.shared.log("MobileStart OK за \(self.ms(t0: s1)) мс. Жду готовности (waitReady, таймаут 40000 мс)…")
                let s2 = Date()
                try OLCCore.waitReady(timeoutMillis: 40000)
                TunnelLog.shared.log("waitReady OK за \(self.ms(t0: s2)) мс — ядро готово, SOCKS поднят")
            } catch {
                TunnelLog.shared.log("ОШИБКА ядра (\(self.ms(t0: t0)) мс): \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            // 3) Сетевые настройки туннеля
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
            let ipv4 = NEIPv4Settings(addresses: [OLC.tunnelIP], subnetMasks: [OLC.tunnelMask])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4
            let dnsHost = cfg.dns.split(separator: ":").first.map(String.init) ?? OLC.defaultDNS
            settings.dnsSettings = NEDNSSettings(servers: [dnsHost])
            settings.mtu = 1500
            TunnelLog.shared.log("Применяю сетевые настройки (dns=\(dnsHost), mtu=1500, default route)…")

            self.setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self else { return }
                if let error = error {
                    TunnelLog.shared.log("ОШИБКА setTunnelNetworkSettings: \(error.localizedDescription)")
                    completionHandler(error)
                    return
                }
                // 4) tun2socks: packetFlow <-> 127.0.0.1:socksPort
                if let fd = Tun2Socks.tunnelFileDescriptor() {
                    TunnelLog.shared.log("utun fd найден: \(fd)")
                } else {
                    TunnelLog.shared.log("ВНИМАНИЕ: utun fd не найден — tun2socks не прочитает пакеты")
                }
                self.tun2socks = Tun2Socks(packetFlow: self.packetFlow,
                                           socksHost: "127.0.0.1",
                                           socksPort: cfg.socksPort,
                                           logLevel: cfg.debug ? "info" : "warn")
                self.tun2socks?.start()
                TunnelLog.shared.log("=== Туннель запущен (всего \(self.ms(t0: t0)) мс) ===")
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        TunnelLog.shared.log("Остановка туннеля (reason=\(reason.rawValue) \(Self.reasonText(reason)))")
        tun2socks?.stop()
        tun2socks = nil
        OLCCore.stop()
        completionHandler()
    }

    /// Человекочитаемая расшифровка NEProviderStopReason для лога.
    private static func reasonText(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none: return "none"
        case .userInitiated: return "userInitiated"
        case .providerFailed: return "providerFailed"
        case .noNetworkAvailable: return "noNetworkAvailable"
        case .unrecoverableNetworkChange: return "unrecoverableNetworkChange"
        case .providerDisabled: return "providerDisabled"
        case .authenticationCanceled: return "authenticationCanceled"
        case .configurationFailed: return "configurationFailed"
        case .idleTimeout: return "idleTimeout"
        case .sessionDisconnected: return "sessionDisconnected"
        case .persistentConnectionFailed: return "persistentConnectionFailed"
        case .configurationReadOnly: return "configurationReadOnly"
        case .configurationStale: return "configurationStale"
        case .superceded: return "superceded"
        case .userLogout: return "userLogout"
        case .userSwitch: return "userSwitch"
        case .connectionFailed: return "connectionFailed"
        case .sleep: return "sleep"
        case .appUpdate: return "appUpdate"
        @unknown default: return "unknown"
        }
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        let cmd = String(data: messageData, encoding: .utf8) ?? ""
        switch cmd {
        case "getlog":
            completionHandler?(Data(TunnelLog.shared.dump().utf8))
        case "clearlog":
            TunnelLog.shared.clear()
            completionHandler?(Data("ok".utf8))
        default:
            // Простой ping/health канал от app -> extension
            let running = OLCCore.isRunning()
            completionHandler?(Data([running ? 1 : 0]))
        }
    }

    private func ms(t0: Date) -> Int { Int(Date().timeIntervalSince(t0) * 1000) }
}
