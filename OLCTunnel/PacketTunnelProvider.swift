import NetworkExtension
import os.log

/// Основной класс расширения VPN-туннеля.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = OSLog(subsystem: "com.you.olcvpn.OLCTunnel", category: "tunnel")
    private var tun2socks: Tun2Socks?

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let cfg = SharedConfig.loadActive() else {
            os_log("Нет активного конфига", log: log, type: .error)
            completionHandler(NSError(domain: "olc", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Нет активного профиля"]))
            return
        }

        // 1) Настройка ядра olcRTC
        OLCCore.setProviders()
        OLCCore.setTransport(cfg.transport)
        OLCCore.setDNS(cfg.dns)
        OLCCore.setDebug(true)

        // 2) Запуск SOCKS5 ядра в фоне
        do {
            try OLCCore.start(carrier: cfg.carrier, roomID: cfg.roomID,
                              clientID: cfg.clientID, keyHex: cfg.keyHex,
                              socksPort: cfg.socksPort)
            try OLCCore.waitReady(timeoutMillis: 15000)
        } catch {
            os_log("Ядро не стартовало: %{public}@", log: log, type: .error,
                   error.localizedDescription)
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

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error = error {
                os_log("setTunnelNetworkSettings: %{public}@", log: self.log, type: .error,
                       error.localizedDescription)
                completionHandler(error)
                return
            }
            // 4) tun2socks: packetFlow <-> 127.0.0.1:socksPort
            self.tun2socks = Tun2Socks(packetFlow: self.packetFlow,
                                       socksHost: "127.0.0.1",
                                       socksPort: cfg.socksPort)
            self.tun2socks?.start()
            os_log("Туннель запущен", log: self.log, type: .info)
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("Остановка туннеля: %d", log: log, type: .info, reason.rawValue)
        tun2socks?.stop()
        tun2socks = nil
        OLCCore.stop()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        // Простой ping/health канал от app -> extension
        let running = OLCCore.isRunning()
        completionHandler?(Data([running ? 1 : 0]))
    }
}
