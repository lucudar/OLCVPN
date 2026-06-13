import Foundation
import Combine
import Darwin

/// Запускает ядро olcRTC ПРЯМО в приложении (не в расширении) и поднимает
/// локальный SOCKS5 на 127.0.0.1. Это прокси-режим (как у автора olcRTC):
/// у ядра в приложении полно памяти и полные логи в одном процессе,
/// поэтому App Group здесь не нужен.
final class ProxyManager: ObservableObject {
    @Published var running = false
    @Published var busy = false
    @Published var status = "Остановлено"
    @Published var lastError: String?
    @Published var testResult: String?
    @Published var log: [String] = []

    private(set) var activeSocksPort = OLC.socksPort

    private func ui(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    private func append(_ s: String) {
        DiagLog.log(s, tag: "proxy")
        let line = "[\(ProxyManager.ts())] \(s)"
        ui { self.log.append(line) }
    }

    private static func ts() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private static func ms(_ from: Date) -> Int { Int(Date().timeIntervalSince(from) * 1000) }

    /// Запуск ядра в приложении.
    func start(profile: Profile, keyHex: String, debug: Bool) {
        guard !busy && !running else { return }
        activeSocksPort = profile.socksPort
        ui {
            self.busy = true
            self.lastError = nil
            self.testResult = nil
            self.status = "Запуск ядра…"
            self.log.removeAll()
        }
        let cid = profile.clientID.isEmpty ? OLC.defaultClientID : profile.clientID
        append("Старт прокси: carrier=\(profile.carrier.rawValue) transport=\(profile.transport.rawValue) room=\(profile.roomID) clientID=\(cid) socks=127.0.0.1:\(profile.socksPort)")
        let p = profile
        let key = keyHex
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let t0 = Date()
            do {
                OLCCore.setProviders()
                OLCCore.setTransport(p.transport.rawValue)
                OLCCore.setDNS(p.dns)
                OLCCore.setDebug(debug)
                self.append("MobileStart…")
                let tStart = Date()
                try OLCCore.start(carrier: p.carrier.rawValue, roomID: p.roomID,
                                  clientID: p.clientID.isEmpty ? OLC.defaultClientID : p.clientID,
                                  keyHex: key, socksPort: p.socksPort)
                self.append("MobileStart OK за \(ProxyManager.ms(tStart)) мс. Жду готовности (waitReady, таймаут 40000 мс)…")
                let tReady = Date()
                try OLCCore.waitReady(timeoutMillis: 40000)
                self.append("waitReady OK за \(ProxyManager.ms(tReady)) мс — ядро готово, SOCKS на 127.0.0.1:\(p.socksPort)")
                self.ui {
                    self.running = true
                    self.busy = false
                    self.status = "Ядро работает (SOCKS 127.0.0.1:\(p.socksPort))"
                }
                self.runTest()
            } catch {
                OLCCore.stop()
                self.append("ОШИБКА ядра за \(ProxyManager.ms(t0)) мс: \(error.localizedDescription)")
                self.ui {
                    self.lastError = error.localizedDescription
                    self.status = "Ошибка запуска ядра"
                    self.busy = false
                    self.running = false
                }
            }
        }
    }

    func stop() {
        append("Остановка ядра")
        DispatchQueue.global(qos: .userInitiated).async {
            OLCCore.stop()
        }
        ui {
            self.running = false
            self.status = "Остановлено"
            self.testResult = nil
        }
    }

    private enum SocksTestResult {
        case success((String, Int))
        case failure(String)
    }

    /// Проверка связи через локальный SOCKS5 (сырой сокет — URLSession на iOS
    /// SOCKS не поддерживает). Делаем SOCKS5-рукопожатие к 127.0.0.1:port,
    /// CONNECT к icanhazip.com:80 и обычный HTTP GET. Возвращает внешний IP.
    func runTest() {
        let port = activeSocksPort
        append("Проверка связи: SOCKS5 → icanhazip.com:80 через 127.0.0.1:\(port)…")
        ui { self.testResult = "Проверяю…" }
        let t0 = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = ProxyManager.socks5HttpGet(host: "icanhazip.com", port: 80,
                                                     socksHost: "127.0.0.1", socksPort: port,
                                                     timeoutSec: 15)
            switch result {
            case .success(let (ip, code)):
                self.append("Тест: OK — внешний IP=\(ip), HTTP=\(code), \(ProxyManager.ms(t0)) мс")
                self.ui { self.testResult = "✅ Связь есть за \(ProxyManager.ms(t0)) мс\nВнешний IP: \(ip) (HTTP \(code))" }
            case .failure(let msg):
                self.append("Тест: ОШИБКА — \(msg) (\(ProxyManager.ms(t0)) мс)")
                self.ui { self.testResult = "❌ Нет связи через прокси: \(msg)" }
            }
        }
    }

    /// Блокирующий SOCKS5-клиент на POSIX-сокетах. Выполнять только в фоне.
    private static func socks5HttpGet(host: String, port: UInt16,
                                      socksHost: String, socksPort: Int,
                                      timeoutSec: Int) -> SocksTestResult {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return .failure("socket() не создан") }
        defer { close(fd) }

        var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(socksPort).bigEndian)
        inet_pton(AF_INET, socksHost, &addr.sin_addr)
        let connRes = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connRes != 0 {
            return .failure("не подключился к SOCKS 127.0.0.1:\(socksPort): \(String(cString: strerror(errno)))")
        }

        func sendAll(_ bytes: [UInt8]) -> Bool {
            var sent = 0
            bytes.withUnsafeBytes { raw in
                while sent < bytes.count {
                    let n = send(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                    if n <= 0 { break }
                    sent += n
                }
            }
            return sent == bytes.count
        }
        func recvN(_ n: Int) -> [UInt8]? {
            var buf = [UInt8](repeating: 0, count: n)
            var got = 0
            while got < n {
                let r = buf.withUnsafeMutableBytes { raw in
                    recv(fd, raw.baseAddress!.advanced(by: got), n - got, 0)
                }
                if r <= 0 { return nil }
                got += r
            }
            return buf
        }

        // 1) Приветствие: VER=5, 1 метод, NO-AUTH
        if !sendAll([0x05, 0x01, 0x00]) { return .failure("не отправил SOCKS greeting") }
        guard let g = recvN(2), g[0] == 0x05, g[1] == 0x00 else {
            return .failure("SOCKS greeting отклонён")
        }

        // 2) CONNECT host:port (ATYP=domain)
        let hostBytes = Array(host.utf8)
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(hostBytes.count)]
        req.append(contentsOf: hostBytes)
        req.append(UInt8(port >> 8))
        req.append(UInt8(port & 0xff))
        if !sendAll(req) { return .failure("не отправил SOCKS CONNECT") }

        guard let head = recvN(4) else { return .failure("нет ответа на CONNECT") }
        if head[1] != 0x00 { return .failure("SOCKS CONNECT отказ, код=\(head[1])") }
        let atyp = head[3]
        let addrLen: Int
        switch atyp {
        case 0x01: addrLen = 4
        case 0x04: addrLen = 16
        case 0x03:
            guard let l = recvN(1) else { return .failure("плохой ответ ATYP domain") }
            addrLen = Int(l[0])
        default: return .failure("неизвестный ATYP \(atyp)")
        }
        _ = recvN(addrLen + 2) // bound addr + port

        // 3) HTTP GET через установленный туннель
        let httpReq = "GET / HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: OLCVPN\r\nConnection: close\r\n\r\n"
        if !sendAll(Array(httpReq.utf8)) { return .failure("не отправил HTTP-запрос") }

        var resp = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let r = chunk.withUnsafeMutableBytes { raw in recv(fd, raw.baseAddress!, 4096, 0) }
            if r <= 0 { break }
            resp.append(contentsOf: chunk[0..<r])
            if resp.count > 65536 { break }
        }
        if resp.isEmpty { return .failure("пустой HTTP-ответ (таймаут?)") }
        guard let text = String(bytes: resp, encoding: .utf8) else {
            return .failure("не декодировал ответ")
        }

        var code = 0
        if let firstLine = text.split(separator: "\r\n").first {
            let parts = firstLine.split(separator: " ")
            if parts.count >= 2 { code = Int(parts[1]) ?? 0 }
        }
        var ip = "?"
        if let range = text.range(of: "\r\n\r\n") {
            let body = String(text[range.upperBound...])
            let lines = body.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
            if let candidate = lines.last(where: { $0.contains(".") || $0.contains(":") }) {
                ip = candidate
            } else {
                ip = body.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return .success((ip, code))
    }
}
