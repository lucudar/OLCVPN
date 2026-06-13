import Foundation
import Darwin

/// Перехватывает stderr/stdout процесса, куда Go-ядро olcRTC пишет свои
/// внутренние логи ([pc]/[ice]/jitsi/smux) — те же строки, что видно на
/// сервере через `journalctl`. Отдаёт их построчно в обработчик, чтобы
/// показывать внутренние логи ядра прямо в приложении.
///
/// Это работает без App Group и без полноценного идентификатора подписи:
/// мы просто дублируем файловый дескриптор 2 (stderr) в свой пайп.
final class CoreLogCapture {
    static let shared = CoreLogCapture()

    private let queue = DispatchQueue(label: "olc.corelog.capture")
    private var started = false
    private var originalStderr: Int32 = -1
    private var readFD: Int32 = -1
    private var writeFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var handler: ((String) -> Void)?

    private init() {}

    /// Запустить перехват (идемпотентно). Повторные вызовы обновляют обработчик.
    func start(_ h: @escaping (String) -> Void) {
        queue.async {
            self.handler = h
            guard !self.started else { return }

            var fds: [Int32] = [0, 0]
            guard pipe(&fds) == 0 else { return }
            self.readFD = fds[0]
            self.writeFD = fds[1]

            // Сделать чтение неблокирующим.
            let flags = fcntl(self.readFD, F_GETFL)
            _ = fcntl(self.readFD, F_SETFL, flags | O_NONBLOCK)

            // Сохранить оригинальный stderr, чтобы дублировать туда вывод
            // (консоль Xcode продолжит показывать логи).
            self.originalStderr = dup(STDERR_FILENO)

            // Перенаправить stderr и stdout в наш пайп.
            dup2(self.writeFD, STDERR_FILENO)
            dup2(self.writeFD, STDOUT_FILENO)
            setvbuf(stderr, nil, _IONBF, 0)
            setvbuf(stdout, nil, _IONBF, 0)

            let src = DispatchSource.makeReadSource(fileDescriptor: self.readFD, queue: self.queue)
            src.setEventHandler { [weak self] in
                guard let self else { return }
                var tmp = [UInt8](repeating: 0, count: 8192)
                let n = read(self.readFD, &tmp, tmp.count)
                if n > 0 {
                    // Эхо в оригинальный stderr.
                    if self.originalStderr >= 0 {
                        _ = write(self.originalStderr, tmp, n)
                    }
                    self.consume(Data(tmp[0..<n]))
                }
            }
            src.resume()
            self.readSource = src
            self.started = true
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !lineData.isEmpty,
                  let raw = String(data: lineData, encoding: .utf8) else { continue }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            // Пропускаем наши собственные NSLog-строки, чтобы не дублировать.
            if line.contains("[OLCVPN]") { continue }
            handler?(line)
        }
        // Защита от разрастания на очень длинной незавершённой строке.
        if buffer.count > 1_000_000 { buffer.removeAll(keepingCapacity: false) }
    }
}
