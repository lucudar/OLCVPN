import Foundation
import NetworkExtension

/// Полная интеграция hev-socks5-tunnel: TUN (utun fd) -> SOCKS5 127.0.0.1:port.
///
/// Движок линкуется как libhev-socks5-tunnel.a (собирается build.sh).
/// Объявления C-функций — в OLCTunnel-Bridging-Header.h.
final class Tun2Socks {
    private let packetFlow: NEPacketTunnelFlow
    private let socksHost: String
    private let socksPort: Int
    private let mtu: Int
    private let logLevel: String
    private var worker: Thread?

    init(packetFlow: NEPacketTunnelFlow, socksHost: String, socksPort: Int,
         mtu: Int = 1500, logLevel: String = "warn") {
        self.packetFlow = packetFlow
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.mtu = mtu
        // hev-socks5-tunnel: «debug»/«info»/«warn»/«error». По умолчанию warn,
        // PacketTunnelProvider при debug-конфиге передаёт «info», чтобы видеть
        // установку соединений и проблемы рукопожатия SOCKS.
        self.logLevel = logLevel
    }

    func start() {
        guard let fd = resolveTunFd() else {
            TunnelLog.shared.log("НЕ нашёл tun fd — пакеты не пойдут", tag: "tun2socks")
            return
        }
        let config = makeConfig()
        TunnelLog.shared.log("старт fd=\(fd) -> \(socksHost):\(socksPort), mtu=\(mtu)", tag: "tun2socks")
        TunnelLog.shared.log("config:\n\(config)", tag: "tun2socks")
        let thread = Thread { [weak self] in
            // self здесь не используется (всё через TunnelLog.shared и захваченные
            // config/fd), но [weak self] оставляем для консистентности с жизненным
            // циклом Tun2Socks: если объект уже освобождён, потоку делать нечего.
            guard self != nil else { return }
            config.withCString { cfg in
                let len = UInt32(strlen(cfg))
                // Блокирующий вызов: работает до hev_socks5_tunnel_quit().
                let rc = cfg.withMemoryRebound(to: UInt8.self, capacity: Int(len)) { ptr in
                    hev_socks5_tunnel_main_from_str(ptr, len, fd)
                }
                TunnelLog.shared.log("hev tunnel завершён, rc=\(rc)", tag: "tun2socks")
            }
        }
        thread.stackSize = 512 * 1024
        thread.name = "olc.tun2socks"
        thread.start()
        worker = thread
    }

    func stop() {
        hev_socks5_tunnel_quit()
        worker = nil
        TunnelLog.shared.log("стоп", tag: "tun2socks")
    }

    /// YAML-конфиг для hev-socks5-tunnel.
    private func makeConfig() -> String {
        """
        tunnel:
          mtu: \(mtu)
        socks5:
          address: \(socksHost)
          port: \(socksPort)
          udp: udp
        misc:
          task-stack-size: 81920
          log-level: \(logLevel)
        """
    }

    /// Получение fd tun-устройства.
    ///
    /// ВАЖНО: НЕ используем packetFlow.value(forKeyPath:) — у NEPacketTunnelFlow нет
    /// такого keyPath, и KVC бросает NSUnknownKeyException. Это Objective-C исключение,
    /// которое Swift НЕ ловит → расширение падает при старте. Поэтому только
    /// безопасный скан utun-интерфейсов (UTUN_OPT_IFNAME).
    private func resolveTunFd() -> Int32? {
        return Tun2Socks.tunnelFileDescriptor()
    }

    /// Запасной способ: находит fd utun-интерфейса перебором + UTUN_OPT_IFNAME.
    /// В расширении может быть НЕСКОЛЬКО utun (системные + наш); берём с наибольшим fd.
    static func tunnelFileDescriptor() -> Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        let UTUN_OPT_IFNAME: Int32 = 2
        let SYSPROTO_CONTROL: Int32 = 2
        var found: [(fd: Int32, name: String)] = []
        for fd in 0..<1024 as Range<Int32> {
            var len = socklen_t(buf.count)
            let ret = getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &buf, &len)
            if ret == 0 {
                let name = String(cString: buf)
                if name.hasPrefix("utun") { found.append((fd, name)) }
            }
        }
        if found.isEmpty {
            TunnelLog.shared.log("utun не найден среди fd 0..1024", tag: "tun2socks")
            return nil
        }
        let list = found.map { "\($0.fd):\($0.name)" }.joined(separator: ", ")
        let chosen = found.max(by: { $0.fd < $1.fd })!
        TunnelLog.shared.log("найдены utun [\(list)], выбран fd=\(chosen.fd) (\(chosen.name))", tag: "tun2socks")
        return chosen.fd
    }
}
