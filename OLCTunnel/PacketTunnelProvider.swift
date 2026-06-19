import NetworkExtension

/// Основной класс расширения VPN-туннеля.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var tun2socks: Tun2Socks?

    /// В Network Extension действует жёсткий лимит памяти (~50 MB). Тяжёлые
    /// видео-транспорты olcRTC (vp8/sei/video) тянут кодеки и легко его пробивают,
    /// что приводит к убийству расширения системой. Поэтому в туннеле принудительно
    /// используем лёгкий `datachannel`. (Эксперименты с тяжёлыми транспортами —
    /// только вне extension.)
    private static let heavyTransports: Set<String> = ["vp8channel", "videochannel", "seichannel"]

    private static func memorySafeTransport(_ t: String) -> String {
        heavyTransports.contains(t.lowercased()) ? "datachannel" : t
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let t0 = Date()
        TunnelLog.shared.clear()
        TunnelLog.shared.log("=== startTunnel вызван ===")

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

        TunnelLog.shared.log("Конфиг [\(source)]: carrier=\(cfg.carrier) transport=\(cfg.transport) room=\(cfg.roomID) clientID='\(cfg.clientID)' dns=\(cfg.dns) socksPort=\(cfg.socksPort) keyLen=\(cfg.keyHex.count) debugProfile=\(cfg.debug) whitelist=\(cfg.whitelist.count)")

        // Защита памяти extension: тяжёлые транспорты принудительно → datachannel.
        let transport = Self.memorySafeTransport(cfg.transport)
        if transport != cfg.transport {
            TunnelLog.shared.log("⚠️ transport=\(cfg.transport) тяжёлый для NE (лимит ~50MB) → принудительно \(transport)")
        }

        DiagLog.debugEnabled = cfg.debug

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            CoreLogCapture.shared.start { line in
                TunnelLog.shared.log(line, tag: "core")
            }
            OLCCore.setLogWriter(CoreLogWriter { line in
                TunnelLog.shared.log(line, tag: "core")
            })
            TunnelLog.shared.log("Capture логов ядра подключен (stderr + log.SetOutput)")

            OLCCore.setProviders()
            OLCCore.setTransport(transport)
            OLCCore.setDNS(cfg.dns)
            OLCCore.setDebug(true)
            TunnelLog.shared.log("Ядро сконфигурировано (transport=\(transport), dns=\(cfg.dns), debug=true)")

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

            // Сетевые настройки туннеля
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
            let ipv4 = NEIPv4Settings(addresses: [OLC.tunnelIP], subnetMasks: [OLC.tunnelMask])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4
            let dnsHost = cfg.dns.split(separator: ":").first.map(String.init) ?? OLC.defaultDNS
            settings.dnsSettings = NEDNSSettings(servers: [dnsHost])
            settings.mtu = 1500

            // Белый список: резолвим домены → IP, добавляем excludedRoutes
            if !cfg.whitelist.isEmpty {
                let excludedRoutes = self.resolveWhitelist(cfg.whitelist)
                if !excludedRoutes.isEmpty {
                    ipv4.excludedRoutes = excludedRoutes
                    TunnelLog.shared.log("Белый список: \(excludedRoutes.count) маршрутов исключено из туннеля")
                }
            }

            TunnelLog.shared.log("Применяю сетевые настройки (dns=\(dnsHost), mtu=1500, default route, excluded=\(ipv4.excludedRoutes?.count ?? 0))…")

            self.setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self else { return }
                if let error = error {
                    TunnelLog.shared.log("ОШИБКА setTunnelNetworkSettings: \(error.localizedDescription)")
                    completionHandler(error)
                    return
                }
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
        case .userLogout: return "userLogout"
        case .userSwitch: return "userSwitch"
        case .connectionFailed: return "connectionFailed"
        case .sleep: return "sleep"
        case .appUpdate: return "appUpdate"
        @unknown default: return "unknown(\(reason.rawValue))"
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
            let running = OLCCore.isRunning()
            completionHandler?(Data([running ? 1 : 0]))
        }
    }

    private func ms(t0: Date) -> Int { Int(Date().timeIntervalSince(t0) * 1000) }

    // MARK: - Белый список

    /// Резолвит записи белого списка (домены, IP, CIDR) в массив NEIPv4Route для excludedRoutes.
    /// Каждый резолвинг ограничен 2 секундами; максимум 50 IP на домен.
    private func resolveWhitelist(_ entries: [String]) -> [NEIPv4Route] {
        var routes: [NEIPv4Route] = []
        var seen = Set<String>()

        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespaces).lowercased()
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains("/") {
                // CIDR-нотация (например 192.168.0.0/16)
                if let route = parseCIDR(trimmed), !seen.contains(routeKey(route)) {
                    seen.insert(routeKey(route))
                    routes.append(route)
                    TunnelLog.shared.log("whitelist CIDR: \(trimmed)")
                }
            } else if isValidIPv4(trimmed) {
                // Одиночный IP → /32
                let route = NEIPv4Route(destinationAddress: trimmed, subnetMask: "255.255.255.255")
                if !seen.contains(routeKey(route)) {
                    seen.insert(routeKey(route))
                    routes.append(route)
                    TunnelLog.shared.log("whitelist IP: \(trimmed)")
                }
            } else {
                // Домен — резолвим через getaddrinfo
                let ips = resolveDNS(trimmed)
                var count = 0
                for ip in ips where count < 50 {
                    let route = NEIPv4Route(destinationAddress: ip, subnetMask: "255.255.255.255")
                    if !seen.contains(routeKey(route)) {
                        seen.insert(routeKey(route))
                        routes.append(route)
                        count += 1
                    }
                }
                TunnelLog.shared.log("whitelist DNS: \(trimmed) → \(count) IP")
            }
        }

        return routes
    }

    private func parseCIDR(_ cidr: String) -> NEIPv4Route? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              isValidIPv4(String(parts[0])),
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32
        else { return nil }

        let maskValue = prefix == 0 ? UInt32(0) : UInt32.max << (32 - prefix)
        let mask = String(format: "%d.%d.%d.%d",
                          (maskValue >> 24) & 0xFF,
                          (maskValue >> 16) & 0xFF,
                          (maskValue >> 8) & 0xFF,
                          maskValue & 0xFF)
        return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: mask)
    }

    private func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }
    }

    private func resolveDNS(_ hostname: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?

        let status = getaddrinfo(hostname, nil, &hints, &result)
        guard status == 0, let head = result else {
            TunnelLog.shared.log("whitelist DNS: \(hostname) — ошибка резолвинга (status=\(status))")
            return []
        }
        defer { freeaddrinfo(head) }

        var ips: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = head
        while let node = current {
            if node.pointee.ai_family == AF_INET, let aiAddr = node.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                aiAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    inet_ntop(AF_INET, &sin.pointee.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
                }
                let ip = String(cString: buf)
                if !ip.isEmpty {
                    ips.append(ip)
                }
            }
            current = node.pointee.ai_next
        }
        return ips
    }

    private func routeKey(_ route: NEIPv4Route) -> String {
        "\(route.destinationAddress)/\(route.destinationSubnetMask)"
    }
}
