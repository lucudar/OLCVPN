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
    private var worker: Thread?

    init(packetFlow: NEPacketTunnelFlow, socksHost: String, socksPort: Int, mtu: Int = 1500) {
        self.packetFlow = packetFlow
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.mtu = mtu
    }

    func start() {
        guard let fd = Tun2Socks.tunnelFileDescriptor() else {
            TunnelLog.shared.log("НЕ нашёл utun fd — пакеты не пойдут", tag: "tun2socks")
            return
        }
        let config = makeConfig()
        TunnelLog.shared.log("старт fd=\(fd) -> \(socksHost):\(socksPort), mtu=\(mtu)", tag: "tun2socks")
        TunnelLog.shared.log("config:\n\(config)", tag: "tun2socks")
        let thread = Thread { [weak self] in
            guard let self else { return }
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
          log-level: warn
        """
    }

    /// Находит fd utun-интерфейса, созданного NetworkExtension.
    /// Публичного API нет; стандартный приём — перебор fd + UTUN_OPT_IFNAME.
    ///
    /// ВАЖНО: в расширении может быть НЕСКОЛЬКО utun (системные + наш).
    /// Наш создаётся последним (setTunnelNetworkSettings), поэтому берём utun с
    /// НАИБОЛЬШИМ fd и логируем все найденные, чтобы это было видно в логе.
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
