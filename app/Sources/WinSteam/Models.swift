import Foundation

// MARK: - 圖形後端

enum Backend: String, CaseIterable, Identifiable {
    case d3dmetal, dxmt, dxvk, wined3d

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .d3dmetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wined3d: "WineD3D"
        }
    }

    var summary: String {
        switch self {
        case .d3dmetal: "Apple 的轉譯層，支援 DirectX 11／12，相容性最廣。"
        case .dxmt: "把 DirectX 10／11 轉成 Metal，很多 DX11 遊戲用它比較快。"
        case .dxvk: "經由 Vulkan 轉譯，少數遊戲用它才正常。"
        case .wined3d: "Wine 內建的 OpenGL 轉譯，最慢，其他都不行時再試。"
        }
    }
}

// MARK: - wrapper 狀態（直接讀 Info.plist 與檔案）

struct WrapperState: Equatable {
    var hasWrapper = false
    var hasSteam = false
    var backend: Backend = .wined3d
    /// nil 表示這個範本的 Info.plist 沒有 METAL_HUD 鍵。
    var hud: Bool?
    var msync: Int?
    /// Info.plist 的「Program Name and Path」。安裝到一半時會是 /nothing.exe 或 /SteamSetup.exe，
    /// 這時直接開 wrapper 會跳出 Sikarugir 的設定視窗，所以不能算已安裝。
    var programPath: String?

    var launchTargetIsSteam: Bool { programPath?.lowercased().hasSuffix("/steam.exe") == true }
    var installed: Bool { hasWrapper && hasSteam && launchTargetIsSteam }
    /// 有東西但沒裝完（例如安裝中途被停止）
    var partiallyInstalled: Bool { hasWrapper && !installed }

    static func load() -> WrapperState {
        let fm = FileManager.default
        var s = WrapperState()
        s.hasWrapper = fm.isExecutableFile(atPath: Paths.launcher.path) && fm.fileExists(atPath: Paths.plist.path)
        s.hasSteam = fm.fileExists(atPath: Paths.steamExe.path)
        guard s.hasWrapper,
              let data = try? Data(contentsOf: Paths.plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return s }

        func int(_ key: String) -> Int? {
            if let n = dict[key] as? NSNumber { return n.intValue }
            if let str = dict[key] as? String { return Int(str) }
            return nil
        }
        // 與 CLI 的 current_backend 相同的優先順序
        if int("D3DMETAL") == 1 { s.backend = .d3dmetal }
        else if int("DXMT") == 1 { s.backend = .dxmt }
        else if int("DXVK") == 1 { s.backend = .dxvk }
        else { s.backend = .wined3d }
        s.hud = int("METAL_HUD").map { $0 == 1 }
        s.msync = int("WINEMSYNC")
        s.programPath = dict["Program Name and Path"] as? String
        return s
    }
}

// MARK: - 遊戲設定檔

struct GameProfile: Identifiable, Equatable {
    let id: String          // 檔名（不含 .conf），也是 CLI 的指令名稱
    let name: String
    let appID: String?
    let backend: Backend?
    let backendAlt: Backend?
    let tips: [String]
    let experimental: Bool
    let notes: [String]     // 開頭註解（第一行標題以外）

    /// 只讀取 KEY=value，不當成程式執行（與 CLI 的 conf_get 相同）。
    static func parse(id: String, text: String) -> GameProfile {
        var values: [String: String] = [:]
        var header: [String] = []
        var inHeader = true
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                if inHeader {
                    header.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                }
                continue
            }
            if line.isEmpty { continue }
            inHeader = false
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            guard values[key] == nil else { continue }   // 和 head -n 1 一樣只取第一個
            var value = String(line[line.index(after: eq)...])
            if value.hasPrefix("\"") { value.removeFirst() }
            if value.hasSuffix("\"") { value.removeLast() }
            values[key] = value
        }
        let tips = (values["TIPS"] ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return GameProfile(
            id: id,
            name: values["NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? id,
            appID: values["APPID"].flatMap { $0.isEmpty ? nil : $0 },
            backend: values["BACKEND"].flatMap(Backend.init(rawValue:)),
            backendAlt: values["BACKEND_ALT"].flatMap(Backend.init(rawValue:)),
            tips: tips,
            experimental: header.contains { $0.contains("實驗性") },
            notes: Array(header.dropFirst())
        )
    }

    static func loadAll() -> [GameProfile] {
        // 資料夾本身可能是 symlink，contentsOfDirectory 不會跟著走
        guard let dir = Paths.profiles?.resolvingSymlinksInPath(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "conf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parse(id: url.deletingPathExtension().lastPathComponent, text: text)
            }
    }
}

// MARK: - 環境檢查（解析 winsteam doctor 的 ✓ / ! / ✗）

enum CheckStatus {
    case unknown, pass, warn, fail, missing
}

enum CheckKey: String, CaseIterable, Identifiable {
    case appleSilicon, macOS, rosetta, homebrew, disk, creator, wrapper, steam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSilicon: "Apple Silicon"
        case .macOS: "macOS 版本"
        case .rosetta: "Rosetta 2"
        case .homebrew: "Homebrew"
        case .disk: "可用空間"
        case .creator: "Sikarugir Creator"
        case .wrapper: "Wine wrapper"
        case .steam: "Windows 版 Steam"
        }
    }

    var symbol: String {
        switch self {
        case .appleSilicon: "cpu"
        case .macOS: "apple.logo"
        case .rosetta: "arrow.triangle.2.circlepath"
        case .homebrew: "mug"
        case .disk: "internaldrive"
        case .creator: "hammer"
        case .wrapper: "shippingbox"
        case .steam: "gamecontroller"
        }
    }
}

struct CheckItem: Identifiable {
    let key: CheckKey
    var status: CheckStatus
    var detail: String
    var id: CheckKey { key }
}

struct DoctorReport {
    var items: [CheckKey: CheckItem]
    var nativeSteamRunning = false

    static var placeholder: DoctorReport {
        DoctorReport(items: Dictionary(uniqueKeysWithValues: CheckKey.allCases.map {
            ($0, CheckItem(key: $0, status: .unknown, detail: "檢查中…"))
        }))
    }

    func status(_ key: CheckKey) -> CheckStatus { items[key]?.status ?? .unknown }

    static func parse(_ output: String) -> DoctorReport {
        var report = placeholder
        var native = false
        var seen = Set<CheckKey>()

        for raw in output.components(separatedBy: .newlines) {
            let line = ConsoleModel.stripANSI(raw).trimmingCharacters(in: .whitespaces)
            guard let first = line.first, "✓!✗".contains(first) else { continue }
            let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
            var status: CheckStatus = first == "✓" ? .pass : (first == "!" ? .warn : .fail)

            if text.contains("macOS 版 Steam") { native = true; continue }

            let key: CheckKey
            if text.contains("Apple Silicon") { key = .appleSilicon }
            else if text.hasPrefix("macOS") || text.contains("需要 macOS") { key = .macOS }
            else if text.contains("Rosetta") { key = .rosetta }
            else if text.contains("Homebrew") { key = .homebrew }
            else if text.contains("可用空間") { key = .disk }
            else if text.contains("Sikarugir Creator") { key = .creator }
            else if text.hasPrefix("Wrapper：") || text.contains("尚未建立 wrapper") { key = .wrapper }
            else if text.contains("Steam") { key = .steam }
            else { continue }   // 「基本條件都符合」等總結行

            // 「還沒裝」不算錯誤，安裝流程會處理
            if status == .warn && [.creator, .wrapper, .steam].contains(key) { status = .missing }
            seen.insert(key)
            report.items[key] = CheckItem(key: key, status: status, detail: friendlyDetail(key, status, text))
        }

        // 沒有 wrapper 時 doctor 不會回報 Steam
        if !seen.contains(.steam) {
            report.items[.steam] = CheckItem(key: .steam, status: .missing,
                                             detail: seen.contains(.wrapper) ? "需要先建立 wrapper" : "無法判斷")
        }
        for key in CheckKey.allCases where !seen.contains(key) && key != .steam {
            report.items[key] = CheckItem(key: key, status: .unknown, detail: "沒有取得結果")
        }
        report.nativeSteamRunning = native
        return report
    }

    private static func friendlyDetail(_ key: CheckKey, _ status: CheckStatus, _ text: String) -> String {
        switch (key, status) {
        case (.appleSilicon, .pass): return "這台 Mac 使用 Apple 晶片"
        case (.rosetta, .pass): return "已安裝"
        case (.rosetta, .fail): return "尚未安裝，安裝過程會帶你完成"
        case (.homebrew, .pass): return "已安裝"
        case (.homebrew, .fail): return "需要先到 brew.sh 安裝 Homebrew"
        case (.creator, .pass): return "已安裝"
        case (.creator, .missing): return "尚未安裝，安裝時會用 Homebrew 自動安裝"
        case (.wrapper, .pass):
            return text.hasPrefix("Wrapper：") ? String(text.dropFirst("Wrapper：".count)) : text
        case (.wrapper, .missing): return "尚未建立"
        case (.steam, .pass): return "已安裝"
        case (.steam, .missing): return "尚未安裝"
        default: return text
        }
    }
}

// MARK: - 安裝步驟（對應 winsteam setup 的「▸ N/7」）

struct SetupStep: Identifiable {
    let number: Int
    /// 進階頁、記錄用的短標題
    let title: String
    /// 安裝畫面上給一般使用者看的一句話
    let message: String
    var id: Int { number }

    static let count = 7

    static let all: [SetupStep] = [
        SetupStep(number: 1, title: "檢查環境", message: "正在檢查這台 Mac…"),
        SetupStep(number: 2, title: "Rosetta 2", message: "正在準備 Apple 的 Rosetta 2…"),
        SetupStep(number: 3, title: "Sikarugir Creator", message: "正在安裝 Windows 相容工具…"),
        SetupStep(number: 4, title: "下載 Wine 引擎與範本",
                  message: "正在下載 Windows 相容元件，視網路速度約需幾分鐘到十分鐘…"),
        SetupStep(number: 5, title: "建立 Windows 環境", message: "正在建立 Windows 環境，約需一兩分鐘…"),
        SetupStep(number: 6, title: "安裝 Windows 版 Steam", message: "正在安裝 Windows 版 Steam，通常一分鐘內完成…"),
        SetupStep(number: 7, title: "寫入設定", message: "快好了，正在完成設定…"),
    ]

    static func step(_ n: Int) -> SetupStep? { all.first { $0.number == n } }
}

// MARK: - Steam 實際狀態（winsteam state）

/// `winsteam state` 的輸出：每行 key=value。
struct SteamState: Equatable {
    struct Game: Equatable {
        var appID: String?
        var installed = false
        /// 有安裝記錄但還沒完成（例如下載中）
        var installing = false
    }

    var wrapper = false
    var steamInstalled = false
    /// Steam 用戶端已經更新到最新版
    var clientReady = false
    /// Windows 版 Steam 正在執行
    var running = false
    /// 這份 Steam 記住了至少一個帳號（曾經登入過，不保證此刻仍登入）
    var hasLoggedIn = false
    var games: [String: Game] = [:]

    /// 解析失敗（例如舊版 CLI 沒有 state 指令）時回傳 nil
    static func parse(_ output: String) -> SteamState? {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        guard values["steam_installed"] != nil else { return nil }
        func flag(_ key: String) -> Bool { values[key] == "1" }

        var s = SteamState()
        s.wrapper = flag("wrapper")
        s.steamInstalled = flag("steam_installed")
        s.clientReady = flag("client_ready")
        s.running = flag("running")
        s.hasLoggedIn = flag("has_logged_in")
        for key in values.keys where key.hasPrefix("game.") {
            let parts = key.split(separator: ".")
            guard parts.count == 3 else { continue }
            let id = String(parts[1])
            var g = s.games[id] ?? Game()
            switch parts[2] {
            case "appid": g.appID = values[key].flatMap { $0.isEmpty ? nil : $0 }
            case "installed": g.installed = flag(key)
            case "installing": g.installing = flag(key)
            default: break
            }
            s.games[id] = g
        }
        return s
    }
}
