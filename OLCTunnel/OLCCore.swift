import Foundation
import Olcrtc   // <- модуль из Olcrtc.xcframework (gomobile bind)

/// ЕДИНСТВЕННОЕ место, где мы касаемся gomobile-символов.
///
/// gomobile префиксует экспорты именем фреймворка. При `-o Olcrtc.xcframework`
/// функции обычно имеют вид `MobileStart`, `MobileWaitReady`, и т.д.
/// ЕСЛИ префикс в сгенерированном заголовке иной — поправь только здесь.
enum OLCCore {
    static func setProviders() { MobileSetProviders() }
    static func setTransport(_ t: String) { MobileSetTransport(t) }
    static func setDNS(_ dns: String) { MobileSetDNS(dns) }
    static func setDebug(_ on: Bool) { MobileSetDebug(on) }

    /// Запуск ядра. gomobile мапит `func Start(...) error` в throwing-метод.
    static func start(carrier: String, roomID: String, clientID: String,
                      keyHex: String, socksPort: Int,
                      user: String = "", pass: String = "") throws {
        try MobileStart(carrier, roomID, clientID, keyHex, socksPort, user, pass)
    }

    /// Блокирует до готовности SOCKS5 либо кидает ошибку.
    static func waitReady(timeoutMillis: Int) throws {
        try MobileWaitReady(timeoutMillis)
    }

    static func stop() { MobileStop() }
    static func isRunning() -> Bool { MobileIsRunning() }

    /// Латентность HTTP через туннель (мс). 0 при ошибке.
    static func ping(carrier: String, transport: String, roomID: String,
                     clientID: String, keyHex: String, socksPort: Int) -> Int64 {
        var result: Int64 = 0
        result = (try? MobilePing(carrier, transport, roomID, clientID, keyHex,
                                  socksPort, 10000, "", 30, 8)) ?? 0
        return result
    }

    /// Прокидывает логи ядра в переданный обработчик.
    static func setLogWriter(_ writer: MobileLogWriterProtocol) {
        MobileSetLogWriter(writer)
    }
}
