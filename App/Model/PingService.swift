import Foundation
import Olcrtc

/// Проверка связи через ядро olcRTC (MobilePing). Работает независимо от туннеля.
enum PingService {
    /// Возвращает латентность в мс либо nil при ошибке.
    static func ping(profile: Profile, keyHex: String) async -> Int64? {
        await withCheckedContinuation { (cont: CheckedContinuation<Int64?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var ret: Int64 = 0
                var err: NSError?
                let ok = MobilePing(profile.carrier.rawValue,
                                    profile.transport.rawValue,
                                    profile.roomID,
                                    profile.clientID,
                                    keyHex,
                                    profile.socksPort,
                                    10000, "", 30, 8, &ret, &err)
                if !ok || err != nil || ret <= 0 {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: ret)
                }
            }
        }
    }
}
