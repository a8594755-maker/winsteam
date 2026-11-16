import Foundation

/// 與 bin/winsteam 相同的路徑規則，並尊重同樣的環境變數。
enum Paths {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    private static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// WINSTEAM_WRAPPER，預設 ~/Applications/Sikarugir/Steam.app
    static var wrapper: URL {
        if let v = env["WINSTEAM_WRAPPER"], !v.isEmpty { return expand(v) }
        return home.appendingPathComponent("Applications/Sikarugir/Steam.app")
    }

    /// WINSTEAM_CACHE，預設 ~/Library/Application Support/Sikarugir
    static var cache: URL {
        if let v = env["WINSTEAM_CACHE"], !v.isEmpty { return expand(v) }
        return home.appendingPathComponent("Library/Application Support/Sikarugir")
    }

    static var plist: URL { wrapper.appendingPathComponent("Contents/Info.plist") }
    static var launcher: URL { wrapper.appendingPathComponent("Contents/MacOS/Sikarugir") }
    static var steamDir: URL { wrapper.appendingPathComponent("Contents/drive_c/Program Files (x86)/Steam") }
    static var steamExe: URL { steamDir.appendingPathComponent("Steam.exe") }
    static var steamLogs: URL { steamDir.appendingPathComponent("logs") }

    /// 要執行的 CLI。順序：WINSTEAM_CLI（開發用）→ bundle 內的 Resources/bin/winsteam
    /// → 從執行檔往上找儲存庫裡的 bin/winsteam（swift run 時）。
    static var cli: URL? {
        let fm = FileManager.default
        if let v = env["WINSTEAM_CLI"], !v.isEmpty {
            let u = expand(v)
            return fm.isExecutableFile(atPath: u.path) ? u : nil
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("bin/winsteam"),
           fm.isExecutableFile(atPath: res.path) {
            return res
        }
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<7 {
            guard let d = dir else { break }
            let candidate = d.appendingPathComponent("bin/winsteam")
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    /// 和 CLI 一樣：WINSTEAM_PROFILES，否則是 CLI 所在位置的 ../profiles。
    static var profiles: URL? {
        if let v = env["WINSTEAM_PROFILES"], !v.isEmpty { return expand(v) }
        guard let cli else { return nil }
        return cli.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("profiles")
    }

    /// 子行程的環境。從 Finder 開啟的 App 的 PATH 只有 /usr/bin:/bin:/usr/sbin:/sbin，
    /// 找不到 Homebrew，所以補上常見的 Homebrew 位置。
    static func childEnvironment() -> [String: String] {
        var e = env
        let base = e["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let parts = base.split(separator: ":").map(String.init)
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"].filter { !parts.contains($0) }
        e["PATH"] = (extra + parts).joined(separator: ":")
        // 語系刻意不設定（從 Finder 開啟的 App 本來就沒有 LANG）：macOS 的 bash 3.2 在 UTF-8 語系下，
        // 會把 "$var" 後面緊接的中文字當成變數名稱的一部分，在 set -u 下直接結束。
        // CLI 改成一律寫 "${var}" 之前，不要在這裡補 LANG / LC_CTYPE。
        e["TERM"] = "dumb"
        return e
    }
}
