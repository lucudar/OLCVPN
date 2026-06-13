import Foundation
import Combine

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

    /// Проверка связи: HTTP-запрос через локальный SOCKS5 к icanhazip.com.
    /// Возвращает внешний IP — если это адрес выходного узла, прокси работает.
    func runTest() {
        let port = activeSocksPort
        append("Проверка связи: http://icanhazip.com через SOCKS 127.0.0.1:\(port)…")
        ui { self.testResult = "Проверяю…" }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: 1,
            kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort as String: port,
        ]
        let session = URLSession(configuration: cfg)
        let t0 = Date()
        guard let url = URL(string: "http://icanhazip.com") else { return }
        session.dataTask(with: url) { [weak self] data, resp, err in
            guard let self else { return }
            if let err = err {
                self.append("Тест: ОШИБКА — \(err.localizedDescription)")
                self.ui { self.testResult = "❌ Нет связи через прокси: \(err.localizedDescription)" }
                return
            }
            let ip = String(data: data ?? Data(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            self.append("Тест: OK — внешний IP=\(ip), HTTP=\(code), \(ProxyManager.ms(t0)) мс")
            self.ui { self.testResult = "✅ Связь есть за \(ProxyManager.ms(t0)) мс\nВнешний IP: \(ip) (HTTP \(code))" }
        }.resume()
    }
}
