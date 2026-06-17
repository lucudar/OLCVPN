import Foundation
import Olcrtc   // <- модуль из Olcrtc.xcframework (gomobile bind)

/// ЕДИНСТВЕННОЕ место, где мы касаемся gomobile-символов.
///
/// gomobile префиксует экспорты именем фреймворка. При `-o Olcrtc.xcframework`
/// функции обычно имеют вид `OlcrtcStart`, `OlcrtcWaitReady`, и т.д.
/// ЕСЛИ префикс в сгенерированном заголовке иной — поправь только здесь.
///
/// Каждый вызов к Go-ядру логируется: вход (аргументы БЕЗ секрета — keyHex
/// только длиной), успех с длительностью мс, ошибка с domain/code/description.
/// Подробные (фазовые) логи — через DiagLog.debug (только при debugEnabled),
/// ошибки — через DiagLog.error (всегда).
enum OLCCore {
    static func setProviders() {
        MobileSetProviders()
        DiagLog.debug("ядро: setProviders()", tag: "core")
    }
    static func setTransport(_ t: String) {
        MobileSetTransport(t)
        DiagLog.debug("ядро: setTransport=\(t)", tag: "core")
    }
    static func setDNS(_ dns: String) {
        MobileSetDNS(dns)
        DiagLog.debug("ядро: setDNS=\(dns)", tag: "core")
    }
    static func setDebug(_ on: Bool) {
        MobileSetDebug(on)
        DiagLog.debug("ядро: setDebug=\(on)", tag: "core")
    }

    /// Запуск ядра. gomobile мапит `func Start(...) error` в свободную C-функцию
    /// `BOOL MobileStart(..., NSError** error)` — ошибку обрабатываем вручную.
    static func start(carrier: String, roomID: String, clientID: String,
                      keyHex: String, socksPort: Int,
                      user: String = "", pass: String = "") throws {
        // Секрет (keyHex) НЕ дампим — только длину, чтобы знать, что он не пустой.
        DiagLog.debug("ядро: start → carrier=\(carrier) room=\(roomID) clientID=\(clientID) socksPort=\(socksPort) keyLen=\(keyHex.count)", tag: "core")
        let t0 = Date()
        var err: NSError?
        let ok = MobileStart(carrier, roomID, clientID, keyHex, socksPort, user, pass, &err)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let err = err {
            DiagLog.error("ядро: MobileStart NSError за \(ms) мс: domain=\(err.domain) code=\(err.code) \(err.localizedDescription)", tag: "core")
            throw err
        }
        if !ok {
            DiagLog.error("ядро: MobileStart failed (ok=false) за \(ms) мс", tag: "core")
            throw NSError(domain: "OLCCore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "MobileStart failed"])
        }
        DiagLog.debug("ядро: MobileStart OK за \(ms) мс", tag: "core")
    }

    /// Блокирует до готовности SOCKS5 либо кидает ошибку.
    static func waitReady(timeoutMillis: Int) throws {
        DiagLog.debug("ядро: waitReady (timeout=\(timeoutMillis) мс)…", tag: "core")
        let t0 = Date()
        var err: NSError?
        let ok = MobileWaitReady(timeoutMillis, &err)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let err = err {
            DiagLog.error("ядро: MobileWaitReady NSError за \(ms) мс: domain=\(err.domain) code=\(err.code) \(err.localizedDescription)", tag: "core")
            throw err
        }
        if !ok {
            DiagLog.error("ядро: MobileWaitReady timeout (ok=false) за \(ms) мс", tag: "core")
            throw NSError(domain: "OLCCore", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "MobileWaitReady timed out"])
        }
        DiagLog.debug("ядро: MobileWaitReady OK за \(ms) мс", tag: "core")
    }

    static func stop() {
        MobileStop()
        DiagLog.log("ядро: stop()", tag: "core")
    }
    static func isRunning() -> Bool {
        let r = MobileIsRunning()
        DiagLog.debug("ядро: isRunning=\(r)", tag: "core")
        return r
    }

    /// Латентность HTTP через туннель (мс). 0 при ошибке.
    static func ping(carrier: String, transport: String, roomID: String,
                     clientID: String, keyHex: String, socksPort: Int) -> Int64 {
        DiagLog.debug("ядро: ping → carrier=\(carrier) transport=\(transport) room=\(roomID) clientID=\(clientID) keyLen=\(keyHex.count)", tag: "core")
        var ret: Int64 = 0
        var err: NSError?
        let t0 = Date()
        let ok = MobilePing(carrier, transport, roomID, clientID, keyHex,
                            socksPort, 10000, "", 30, 8, &ret, &err)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if !ok || err != nil {
            let desc = err?.localizedDescription ?? "ok=false"
            DiagLog.error("ядро: ping ошибка за \(ms) мс: \(desc)", tag: "core")
            return 0
        }
        DiagLog.debug("ядро: ping OK за \(ms) мс → \(ret) мс", tag: "core")
        return ret
    }

    /// Прокидывает логи ядра в переданный обработчик.
    static func setLogWriter(_ writer: MobileLogWriterProtocol) {
        MobileSetLogWriter(writer)
        DiagLog.debug("ядро: setLogWriter установлен", tag: "core")
    }
}
