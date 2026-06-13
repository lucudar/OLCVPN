import Foundation
import Olcrtc   // <- модуль из Olcrtc.xcframework (gomobile bind)

/// ЕДИНСТВЕННОЕ место, где мы касаемся gomobile-символов.
///
/// gomobile префиксует экспорты именем фреймворка. При `-o Olcrtc.xcframework`
/// функции обычно имеют вид `OlcrtcStart`, `OlcrtcWaitReady`, и т.д.
/// ЕСЛИ префикс в сгенерированном заголовке иной — поправь только здесь.
enum OLCCore {
    static func setProviders() { MobileSetProviders() }
    static func setTransport(_ t: String) { MobileSetTransport(t) }
    static func setDNS(_ dns: String) { MobileSetDNS(dns) }
    static func setDebug(_ on: Bool) { MobileSetDebug(on) }

    /// Запуск ядра. gomobile мапит `func Start(...) error` в свободную C-функцию
    /// `BOOL MobileStart(..., NSError** error)` — ошибку обрабатываем вручную.
    static func start(carrier: String, roomID: String, clientID: String,
                      keyHex: String, socksPort: Int,
                      user: String = "", pass: String = "") throws {
        var err: NSError?
        let ok = MobileStart(carrier, roomID, clientID, keyHex, socksPort, user, pass, &err)
        if let err = err { throw err }
        if !ok {
            throw NSError(domain: "OLCCore", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "MobileStart failed"])
        }
    }

    /// Блокирует до готовности SOCKS5 либо кидает ошибку.
    static func waitReady(timeoutMillis: Int) throws {
        var err: NSError?
        let ok = MobileWaitReady(timeoutMillis, &err)
        if let err = err { throw err }
        if !ok {
            throw NSError(domain: "OLCCore", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "MobileWaitReady timed out"])
        }
    }

    static func stop() { MobileStop() }
    static func isRunning() -> Bool { MobileIsRunning() }

    /// Латентность HTTP через туннель (мс). 0 при ошибке.
    static func ping(carrier: String, transport: String, roomID: String,
                     clientID: String, keyHex: String, socksPort: Int) -> Int64 {
        var ret: Int64 = 0
        var err: NSError?
        let ok = MobilePing(carrier, transport, roomID, clientID, keyHex,
                            socksPort, 10000, "", 30, 8, &ret, &err)
        if !ok || err != nil { return 0 }
        return ret
    }

    /// Прокидывает логи ядра в переданный обработчик.
    static func setLogWriter(_ writer: MobileLogWriterProtocol) {
        MobileSetLogWriter(writer)
    }
}
