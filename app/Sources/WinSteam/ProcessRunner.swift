import Darwin
import Foundation

/// 在偽終端機（pty）裡執行 CLI，串流輸出，並能把使用者的回答寫進 stdin。
///
/// 為什麼用 pty 而不是 Pipe：Apple 的 `softwareupdate --install-rosetta` 會在同一行印出
/// 「Type A and press return to agree」之後等 stdin。stdout 是 pipe 時，C 函式庫會把輸出整塊
/// 緩衝起來，提示可能永遠不會出現；接在 pty 上則會即時送出。
/// 注意：這個 pty 不是子行程的「控制終端機」，所以 CLI 的 `has_tty`（開 /dev/tty）仍然是假，
/// CLI 自己的 y/N 確認要靠 GUI 事先問過使用者、再加 `--yes`。
final class PTYProcess {
    var onOutput: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?

    private let process = Process()
    private var master: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "io.github.winsteam.pty")
    private var pending: [UInt8] = []
    private var finished = false

    init(executable: URL, arguments: [String], environment: [String: String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    }

    var pid: Int32 { process.processIdentifier }

    func start() throws {
        var m: Int32 = -1
        var s: Int32 = -1
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&m, &s, nil, nil, &size) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        master = m
        _ = fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK)

        let slave = FileHandle(fileDescriptor: s, closeOnDealloc: true)
        process.standardInput = slave
        process.standardOutput = slave
        process.standardError = slave

        let src = DispatchSource.makeReadSource(fileDescriptor: m, queue: queue)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(m) }
        source = src
        src.resume()

        process.terminationHandler = { [weak self] p in
            // 等一下讓最後的輸出讀完。不能等 EOF：Wine 的 wineserver 可能繼承 pty 而一直不關。
            self?.queue.asyncAfter(deadline: .now() + 0.25) { self?.finish(p.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            src.cancel()
            try? slave.close()
            throw error
        }
        try? slave.close()   // 子行程已經有自己的一份
    }

    /// 把文字送進子行程的 stdin（就像在終端機打字）。
    func write(_ text: String) {
        queue.async { [master] in
            guard master >= 0 else { return }
            let bytes = Array(text.utf8)
            bytes.withUnsafeBufferPointer { _ = Darwin.write(master, $0.baseAddress, $0.count) }
        }
    }

    /// 停止：先結束子行程的子行程（curl、softwareupdate…），再結束 CLI 本身。
    func terminate() {
        guard process.isRunning else { return }
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-TERM", "-P", String(process.processIdentifier)]
        try? killer.run()
        killer.waitUntilExit()
        process.terminate()
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var got: [UInt8] = []
        while true {
            let n = buffer.withUnsafeMutableBytes { read(master, $0.baseAddress, $0.count) }
            if n > 0 {
                got.append(contentsOf: buffer[0..<n])
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 && errno == EAGAIN {
                break
            } else {
                // EOF 或 EIO：所有持有 pty 的行程都結束了
                source?.cancel()
                break
            }
        }
        if !got.isEmpty { emit(got, final: false) }
    }

    private func finish(_ status: Int32) {
        guard !finished else { return }
        finished = true
        drain()
        emit([], final: true)
        source?.cancel()
        let cb = onExit
        DispatchQueue.main.async { cb?(status) }
    }

    /// UTF-8 字元可能被切在兩次 read 之間，把不完整的尾巴留到下一次。
    private func emit(_ bytes: [UInt8], final: Bool) {
        pending.append(contentsOf: bytes)
        var cut = pending.count
        if !final {
            var i = pending.count - 1
            var trailing = 0
            while i >= 0 && trailing < 4 {
                let b = pending[i]
                if b & 0xC0 == 0x80 { trailing += 1; i -= 1; continue }
                let need = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1
                if trailing + 1 < need { cut = i }
                break
            }
        }
        guard cut > 0 else { return }
        let text = String(decoding: pending[0..<cut], as: UTF8.self)
        pending.removeFirst(cut)
        let cb = onOutput
        DispatchQueue.main.async { cb?(text) }
    }
}

/// 一次性的指令（例如 doctor），用 Pipe 收集全部輸出。
enum CommandCapture {
    static func run(_ executable: URL, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = executable
                p.arguments = arguments
                p.environment = Paths.childEnvironment()
                p.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: (-1, "\(error.localizedDescription)"))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
