import Foundation
import Olcrtc

/// Проверка связи через ядро olcRTC (MobilePing). Работает независимо от туннеля.
enum PingService {
    /// Возвращает латентность в мс либо nil при ошибке.
    ///
    /// Делегирует в OLCCore.ping, который уже подробно логирует вызов MobilePing
    /// (домен/код NSError, тайминги). Здесь — только вход/выход сервисного уровня.
    static func ping(profile: Profile, keyHex: String) async -> Int64? {
        DiagLog.debug("PingService: старт carrier=\(profile.carrier.rawValue) transport=\(profile.transport.rawValue) room=\(profile.roomID) keyLen=\(keyHex.count)", tag: "ping")
        let t0 = Date()
        let ret = await withCheckedContinuation { (cont: CheckedContinuation<Int64?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = OLCCore.ping(carrier: profile.carrier.rawValue,
                                     transport: profile.transport.rawValue,
                                     roomID: profile.roomID,
                                     clientID: profile.clientID,
                                     keyHex: keyHex,
                                     socksPort: profile.socksPort)
                cont.resume(returning: r > 0 ? r : nil)
            }
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let ret {
            DiagLog.debug("PingService: OK \(ret) мс (всего \(ms) мс)", tag: "ping")
        } else {
            DiagLog.error("PingService: недоступно (всего \(ms) мс)", tag: "ping")
        }
        return ret
    }
}
