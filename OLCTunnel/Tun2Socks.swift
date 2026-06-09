import Foundation
import NetworkExtension
import os.log

/// Полная интеграция hev-socks5-tunnel: TUN (utun fd) -> SOCKS5 127.0.0.1:port.
///
/// Движок линкуется как libhev-socks5-tunnel.a (собирается build.sh).
/// Объявления C-функций — в OLCTunnel-Bridging-Header.h.
final class Tun2Socks {
    private let packetFlow: NEPacketTunnelFlow
    private let socksHost: String
    private let socksPort: Int
    private let mtu: Int
    private let log = OSLog(subsystem: "com.you.olcvpn.OLCTunnel", category: "tun2socks")
    private var worker: Thread?

    init(packetFlow: NEPacketTunnelFlow, socksHost: String, socksPort: Int, mtu: Int = 1500) {
        self.packetFlow = packetFlow
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.mtu = mtu
    }

    func start() {
        guard let fd = Tun2Socks.tunnelFileDescriptor() else {
            os_log("Не нашёл utun fd", log: log, type: .error)
            return
        }
        let config = makeConfig()
        let thread = Thread { [weak self] in
            guard let self else { return }
            config.withCString { cfg in
                let len = UInt32(strlen(cfg))
                // Блокирующий вызов: работает до hev_socks5_tunnel_quit().
                let rc = cfg.withMemoryRebound(to: UInt8.self, capacity: Int(len)) { ptr in
                    hev_socks5_tunnel_main_from_str(ptr, len, fd)
                }
                os_log("hev tunnel завершён, rc=%d", log: self.log, type: .info, rc)
            }
        }
        thread.stackSize = 512 * 1024
        thread.name = "olc.tun2socks"
        thread.start()
        worker = thread
        os_log("tun2socks старт fd=%d -> %{public}@:%d", log: log, type: .info,
               fd, socksHost, socksPort)
    }

    func stop() {
        hev_socks5_tunnel_quit()
        worker = nil
        os_log("tun2socks стоп", log: log, type: .info)
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

    /// Находит файловый дескриптор utun-интерфейса, созданного NetworkExtension.
    /// Публичного API нет; стандартный приём — перебор fd + UTUN_OPT_IFNAME.
    static func tunnelFileDescriptor() -> Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        let UTUN_OPT_IFNAME: Int32 = 2
        let SYSPROTO_CONTROL: Int32 = 2
        for fd in 0..<1024 as Range<Int32> {
            var len = socklen_t(buf.count)
            let ret = getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &buf, &len)
            if ret == 0, String(cString: buf).hasPrefix("utun") {
                return fd
            }
        }
        return nil
    }
}
