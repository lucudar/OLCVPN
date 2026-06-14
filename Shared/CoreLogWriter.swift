import Foundation
import Olcrtc

/// Мост между Go-логом ядра olcRTC и нашим UI.
///
/// В пакете mobile определён интерфейс:
///     type LogWriter interface { WriteLog(msg string) }
///     func SetLogWriter(w LogWriter) { log.SetOutput(&logBridge{w: w}) }
/// gomobile превращает его в Objective-C протокол `MobileLogWriterProtocol`
/// с методом `-(void)writeLog:(NSString*)msg`, то есть в Swift это
/// `func writeLog(_ msg: String)`.
///
/// После OLCCore.setLogWriter(...) весь вывод стандартного Go `log`
/// (строки `[pc] ...`, `[ice] ...`, `jitsi: ...`, `smux ...`) приходит сюда —
/// независимо от того, отдаёт ли iOS stderr процесса.
final class CoreLogWriter: NSObject, MobileLogWriterProtocol {
    private let handler: (String) -> Void

    init(_ handler: @escaping (String) -> Void) {
        self.handler = handler
        super.init()
    }

    /// Вызывается ядром (через logBridge.Write) на каждый log.Print.
    /// msg обычно содержит префикс даты/времени Go-лога и хвостовой \n.
    func writeLog(_ msg: String) {
        handler(msg)
    }
}
