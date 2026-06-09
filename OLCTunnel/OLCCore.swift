import Foundation
import Olcrtc   // <- модуль из Olcrtc.xcframework (gomobile bind)

/// ЕДИНСТВЕННОЕ место, где мы касаемся gomobile-символов.
///
/// gomobile префиксует экспорты именем фреймворка. При `-o Olcrtc.xcframework`
/// функции обычно имеют вид `OlcrtcStart`, `OlcrtcWaitReady`, и т.д.
/// ЕСЛИ префикс в сгенерированном заголовке иной — поправь только здесь.
enum OLCCore {
    static func setProviders() { OlcrtcSetProviders() }
    static func setTransport(_ t: String) { OlcrtcSetTransport(t) }
    static func setDNS(_ dns: String) { OlcrtcSetDNS(dns) }
    static func setDebug(_ on: Bool) { OlcrtcSetDebug(on) }

    /// Запуск ядра. gomobile мапит `func Start(...) error` в throwing-метод.
    static func start(carrier: String, roomID: String, clientID: String,
                      keyHex: String, socksPort: Int,
                      user: String = "", pass: String = "") throws {
        try OlcrtcStart(carrier, roomID, clientID, keyHex, socksPort, user, pass)
    }

    /// Блокирует до готовности SOCKS5 либо кидает ошибку.
    static func waitReady(timeoutMillis: Int) throws {
        try OlcrtcWaitReady(timeoutMillis)
    }

    static func stop() { OlcrtcStop() }
    static func isRunning() -> Bool { OlcrtcIsRunning() }

    /// Латентность HTTP через туннель (мс). 0 при ошибке.
    static func ping(carrier: String, transport: String, roomID: String,
                     clientID: String, keyHex: String, socksPort: Int) -> Int64 {
        var result: Int64 = 0
        result = (try? OlcrtcPing(carrier, transport, roomID, clientID, keyHex,
                                  socksPort, 10000, "", 30, 8)) ?? 0
        return result
    }

    /// Прокидывает логи ядра в переданный обработчик.
    static func setLogWriter(_ writer: OlcrtcLogWriterProtocol) {
        OlcrtcSetLogWriter(writer)
    }
}
