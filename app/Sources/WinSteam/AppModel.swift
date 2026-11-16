import AppKit
import Foundation
import Observation

enum JobKind: Equatable {
    case setup
    case dryRun
    case openSteam
    case play(String)
    case backend
    case hud
    case kill
    case logs
    case status
    case uninstall
}

struct Job {
    let kind: JobKind
    let title: String
}

/// 首頁上的安裝狀態
struct SetupProgress {
    var active = false
    var currentStep = 0
    /// 已看到「✓ 安裝完成」，接下來 CLI 會自己開啟 Steam
    var finishing = false
    /// nil = 還沒結束；true / false = 成功 / 失敗
    var succeeded: Bool?
    var failure: String?
    /// 靜默安裝失敗，CLI 改跳出 Steam 安裝精靈（需要使用者自己點）
    var wizardFallback = false
    /// 目前下載檔案的百分比（curl 進度列）
    var downloadPercent: Int?

    var fraction: Double {
        if succeeded == true || finishing { return 1 }
        guard currentStep > 0 else { return 0.02 }
        return (Double(currentStep) - 0.5) / Double(SetupStep.count)
    }

    var message: String {
        if finishing { return "安裝好了，正在開啟 Steam…" }
        guard let step = SetupStep.step(currentStep) else { return "準備中…" }
        if currentStep == 4, let p = downloadPercent { return step.message + "（\(p)%）" }
        return step.message
    }
}

struct LicensePrompt: Identifiable {
    let id = UUID()
    let text: String
}

/// 動作開始前需要先問使用者的事
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    let action: () -> Void
}

enum Route: Hashable {
    case advanced
}

@MainActor
@Observable
final class AppModel {
    var path: [Route] = []
    var report = DoctorReport.placeholder
    var checking = false
    var wrapper = WrapperState()
    var profiles: [GameProfile] = []
    let console = ConsoleModel()

    private(set) var job: Job?
    var setup = SetupProgress()
    /// 剛裝好：首頁顯示「請在 Steam 視窗登入」
    var justInstalled = false
    var licensePrompt: LicensePrompt?
    var confirmation: PendingConfirmation?
    var errorMessage: String?
    /// 已經按過「開始遊戲」的設定檔，顯示它們的小提醒
    var launchedProfiles: Set<String> = []
    /// 剛按下、還沒寫進 Info.plist 的值，讓控制項不會跳回舊值
    var pendingBackend: Backend?
    var pendingHUD: Bool?
    private(set) var loaded = false

    @ObservationIgnored private var runner: PTYProcess?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var licenseScanFrom = 0
    @ObservationIgnored private var sawShellError = false
    @ObservationIgnored private var lastErrorLine: String?

    var isBusy: Bool { job != nil }
    var installed: Bool { wrapper.installed }
    var cliAvailable: Bool { Paths.cli != nil }

    // MARK: 狀態

    func reloadLocal() {
        wrapper = WrapperState.load()
        profiles = GameProfile.loadAll()
    }

    func refresh() async {
        reloadLocal()
        loaded = true
        guard let cli = Paths.cli else {
            errorMessage = "找不到 winsteam 命令列工具，請重新下載 WinSteam。"
            return
        }
        checking = true
        let result = await CommandCapture.run(cli, ["doctor"])
        report = DoctorReport.parse(result.output)
        checking = false
        reloadLocal()
    }

    // MARK: 執行 CLI

    private func runCLI(_ args: [String], kind: JobKind, title: String,
                        completion: ((Int32) -> Void)? = nil) {
        guard job == nil else { return }
        guard let cli = Paths.cli else {
            errorMessage = "找不到 winsteam 命令列工具，請重新下載 WinSteam。"
            return
        }
        console.flushPartial()
        console.add("$ winsteam " + args.map(Self.shellQuote).joined(separator: " "), kind: .command)

        let p = PTYProcess(executable: cli, arguments: args, environment: Paths.childEnvironment())
        p.onOutput = { [weak self] text in
            MainActor.assumeIsolated { self?.handleOutput(text) }
        }
        p.onExit = { [weak self] status in
            MainActor.assumeIsolated { self?.jobFinished(status, completion) }
        }
        do {
            try p.start()
            runner = p
            job = Job(kind: kind, title: title)
            licenseScanFrom = console.nextID
            sawShellError = false
            lastErrorLine = nil
        } catch {
            console.add("✗ 無法執行 winsteam：\(error.localizedDescription)", kind: .bad)
            errorMessage = "無法執行 winsteam：\(error.localizedDescription)"
        }
    }

    private func handleOutput(_ text: String) {
        let lines = console.feed(text)
        for line in lines {
            if ConsoleModel.isShellError(line) { sawShellError = true; lastErrorLine = line }
            if line.hasPrefix("✗") { lastErrorLine = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
        }
        guard job?.kind == .setup else { return }
        for line in lines { observeSetupLine(line) }
        if setup.currentStep == 4 { setup.downloadPercent = Self.percent(in: console.partial) ?? setup.downloadPercent }
        checkLicensePrompt(idle: false)
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.checkLicensePrompt(idle: true)
        }
    }

    private func jobFinished(_ exitCode: Int32, _ completion: ((Int32) -> Void)?) {
        idleTask?.cancel()
        console.flushPartial()
        var status = exitCode
        if status == 0 && sawShellError {
            status = 1
            console.add("✗ winsteam 執行時發生錯誤（見上方），雖然它回報成功，WinSteam 仍把這次當成失敗。", kind: .bad)
        }
        console.add(status == 0 ? "— 完成" : "— 結束（代碼 \(exitCode)）", kind: .note)
        let kind = job?.kind
        runner = nil
        job = nil
        licensePrompt = nil

        if kind == .setup {
            setup.active = false
            // 新版 CLI 成功後會自己執行 run；以「安裝完成」或走到第 7 步為準
            if status == 0 && !(setup.finishing || setup.currentStep >= SetupStep.count) { status = 1 }
            if status == 0 {
                reloadLocal()
                if !installed {
                    status = 1
                    setup.failure = "安裝程式說完成了，但找不到可以啟動的 Windows 版 Steam。"
                }
            }
            setup.succeeded = status == 0
            if status == 0 {
                justInstalled = true
            } else if setup.failure == nil {
                setup.failure = lastErrorLine ?? "安裝在第 \(max(setup.currentStep, 1)) 步停下來了。"
            }
            setup.failure = setup.failure.map(Self.friendlyFailure)
        } else if status != 0, let kind, [.openSteam, .backend, .hud, .kill, .uninstall].contains(kind) || isPlay(kind) {
            errorMessage = (lastErrorLine ?? "沒有成功。") + "\n\n詳細過程在「進階」的輸出區。"
        }
        completion?(status)
        pendingBackend = nil
        pendingHUD = nil
        Task { await refresh() }
    }

    private func isPlay(_ kind: JobKind) -> Bool {
        if case .play = kind { return true }
        return false
    }

    func stop() {
        guard let runner else { return }
        console.add("（已要求停止）", kind: .note)
        if job?.kind == .setup { setup.failure = "安裝已停止。" }
        runner.terminate()
    }

    // MARK: 安裝

    /// 使用者在首頁按「安裝」或「重試」。按下這顆按鈕就是同意安裝（按鈕下方有說明會做什麼），
    /// 所以加 --yes 回答 CLI 的「要安裝嗎？」。Apple 的 Rosetta 授權條款不在此列，另外由使用者決定。
    func install() {
        withNativeSteamCheck("安裝完成後開啟 Windows 版 Steam") { [weak self] _ in
            guard let self else { return }
            self.justInstalled = false
            self.setup = SetupProgress(active: true)
            self.runCLI(["--yes", "setup"], kind: .setup, title: "安裝中")
        }
    }

    /// 進階頁的預演，不影響首頁狀態
    func dryRun() {
        runCLI(["--dry-run", "setup"], kind: .dryRun, title: "預演安裝")
    }

    func backToStart() {
        setup = SetupProgress()
    }

    private func observeSetupLine(_ line: String) {
        if line.hasPrefix("▸ ") {
            let rest = line.dropFirst(2)
            if let slash = rest.firstIndex(of: "/"), let n = Int(rest[..<slash]) {
                setup.currentStep = n
                setup.downloadPercent = nil
            }
        } else if line.hasPrefix("✓") && line.contains("安裝完成") {
            setup.finishing = true
        } else if line.contains("改用 Steam 的安裝精靈") {
            setup.wizardFallback = true
        } else if line.hasPrefix("✗") || ConsoleModel.isShellError(line) {
            setup.failure = line.hasPrefix("✗") ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : "安裝程式發生錯誤。"
        }
    }

    /// 把 CLI 的錯誤訊息換成一般人看得懂的一句話；原文在「詳細資訊」裡。
    static func friendlyFailure(_ raw: String) -> String {
        let rules: [(String, String)] = [
            ("下載失敗", "下載沒有成功，可能是網路不穩。確認網路連線後按「重試」。"),
            ("SHA-256", "下載的檔案不完整，已經刪掉了。請按「重試」重新下載。"),
            ("Homebrew", "這台 Mac 還沒有 Homebrew。請先到 brew.sh 照說明安裝（需要用到終端機），裝好後按「重試」。"),
            ("可用空間", "硬碟空間不夠。清出一些空間後按「重試」。"),
            ("找不到 Steam.exe", "Windows 版 Steam 沒有裝成功。請按「重試」再裝一次。"),
            ("Windows 環境不完整", "建立 Windows 環境時出了問題。請按「重試」再試一次。"),
            ("unbound variable", "安裝程式發生內部錯誤。請按「重試」；如果一直出現，請把「詳細資訊」的內容回報給我們。"),
        ]
        if let hit = rules.first(where: { raw.contains($0.0) }) { return hit.1 }
        // 其他情況：拿掉網址與路徑這類技術細節
        var text = raw.replacingOccurrences(of: #"\s*https?://\S+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*/(Users|private|Applications)/\S+"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "：: "))
        return text.isEmpty ? "安裝沒有完成。" : text
    }

    private static func percent(in text: String) -> Int? {
        guard let r = text.range(of: #"(\d{1,3})(\.\d)?%\s*$"#, options: .regularExpression) else { return nil }
        let digits = text[r].prefix { $0.isNumber }
        return Int(digits).map { min($0, 100) }
    }

    // MARK: Rosetta 2 授權

    private static let licenseMarkers = [
        "type a", "type 'a'", "press return to agree", "agree to the terms",
        "software license agreement", "apple slas",
    ]

    /// 偵測 softwareupdate 的授權提示。WinSteam 絕不自動回答：只會跳出視窗，由使用者親自按「我同意」。
    private func checkLicensePrompt(idle: Bool) {
        guard job?.kind == .setup, licensePrompt == nil else { return }
        var recent = Array(console.lines(since: licenseScanFrom).map(\.text).suffix(8))
        if let header = recent.lastIndex(where: { $0.hasPrefix("▸") }) {
            recent = Array(recent[(header + 1)...])   // 只顯示這一步之後的文字
        }
        let partial = console.partial
        let tail = (recent + (partial.isEmpty ? [] : [partial])).joined(separator: "\n")
        let lower = tail.lowercased()
        let waiting = !partial.trimmingCharacters(in: .whitespaces).isEmpty
        let matched = Self.licenseMarkers.contains { lower.contains($0) }
        // 1) 看到 Apple 授權的字樣；或 2) 在 Rosetta 這一步，輸出停在沒換行的一行上兩秒以上
        if matched || (idle && waiting && setup.currentStep == 2) {
            licensePrompt = LicensePrompt(text: tail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func answerLicense(agree: Bool) {
        guard let runner else { licensePrompt = nil; return }
        licenseScanFrom = console.nextID + (console.partial.isEmpty ? 0 : 1)
        licensePrompt = nil
        if agree {
            console.add("（你按下了「我同意」，WinSteam 把 A 送給 Apple 的安裝程式）", kind: .note)
            runner.write("A\n")
        } else {
            console.add("（你沒有同意 Apple 的授權條款，已停止安裝）", kind: .note)
            setup.failure = "沒有同意 Rosetta 2 的授權條款，所以安裝停止了。沒有 Rosetta 2 就無法執行 Windows 版 Steam。"
            runner.terminate()
        }
    }

    /// 備用方案：在「終端機」裡執行 Apple 的安裝程式，讓使用者直接看到原始提示並自己輸入。
    func installRosettaInTerminal() {
        if licensePrompt != nil {
            licensePrompt = nil
            setup.failure = "改用終端機安裝 Rosetta 2。裝好後回到這裡按「重試」。"
            runner?.terminate()
        }
        let script = """
        #!/bin/bash
        clear
        echo "這是 Apple 的 Rosetta 2 安裝程式（由 WinSteam 開啟）。"
        echo "請閱讀下面 Apple 的授權說明。同意的話輸入 A 再按 return；不同意就直接關掉這個視窗。"
        echo
        /usr/sbin/softwareupdate --install-rosetta
        echo
        echo "完成後可以關閉這個視窗，回到 WinSteam 按「重試」。"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WinSteam-安裝Rosetta2.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            errorMessage = "無法開啟終端機：\(error.localizedDescription)"
        }
    }

    // MARK: 啟動（只透過 winsteam run / play，且一定要先確認 Steam 已裝好）

    /// macOS 版 Steam 開著時，CLI 會問要不要先關掉；GUI 先問使用者，同意才加 --yes。
    private func withNativeSteamCheck(_ what: String, run: @escaping (_ yes: Bool) -> Void) {
        Task {
            let r = await CommandCapture.run(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-x", "steam_osx"])
            if r.status == 0 {
                confirmation = PendingConfirmation(
                    title: "要先關閉 macOS 版 Steam",
                    message: "同一個帳號兩邊同時登入，Windows 版會連不上線。要關閉 macOS 版 Steam，再\(what)嗎？",
                    confirmLabel: "關閉並繼續",
                    action: { run(true) })
            } else {
                run(false)
            }
        }
    }

    /// 直接開 wrapper 在沒裝好時會跳出 Sikarugir 的設定視窗，所以先重新確認狀態。
    private func ensureInstalled() -> Bool {
        reloadLocal()
        if !installed {
            errorMessage = "Windows 版 Steam 還沒裝好。請先按「安裝」。"
            return false
        }
        return true
    }

    func openSteam() {
        guard ensureInstalled() else { return }
        withNativeSteamCheck("開啟 Steam") { [weak self] yes in
            self?.runCLI((yes ? ["--yes"] : []) + ["run"], kind: .openSteam, title: "開啟 Steam")
        }
    }

    func play(_ profile: GameProfile, backend: Backend? = nil) {
        guard ensureInstalled() else { return }
        withNativeSteamCheck("開始遊戲") { [weak self] yes in
            var args = (yes ? ["--yes"] : []) + ["play", profile.id]
            if let backend { args += ["--backend", backend.rawValue] }
            self?.runCLI(args, kind: .play(profile.id), title: "開啟 \(profile.name)") { status in
                if status == 0 { self?.launchedProfiles.insert(profile.id) }
            }
        }
    }

    func dismissTips(_ profile: GameProfile) {
        launchedProfiles.remove(profile.id)
    }

    // MARK: 進階

    func setBackend(_ backend: Backend) {
        guard backend != wrapper.backend else { return }
        pendingBackend = backend
        runCLI(["backend", backend.rawValue], kind: .backend, title: "切換圖形後端")
    }

    func setHUD(_ on: Bool) {
        pendingHUD = on
        runCLI(["hud", on ? "on" : "off"], kind: .hud, title: on ? "開啟 Metal HUD" : "關閉 Metal HUD")
    }

    func killWine() { runCLI(["kill"], kind: .kill, title: "結束 Wine 程序") }
    func showLogs() { runCLI(["logs"], kind: .logs, title: "查看記錄") }
    func showStatus() { runCLI(["status"], kind: .status, title: "目前設定") }

    func revealLogs() {
        let fm = FileManager.default
        let target = fm.fileExists(atPath: Paths.steamLogs.path) ? Paths.steamLogs : Paths.wrapper
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// 使用者已在破壞性確認對話框按下「刪除」，才加 --yes。
    func uninstall(all: Bool) {
        runCLI(["--yes", "uninstall"] + (all ? ["--all"] : []), kind: .uninstall, title: "移除") { [weak self] status in
            if status == 0 {
                self?.launchedProfiles.removeAll()
                self?.setup = SetupProgress()
                self?.justInstalled = false
            }
        }
    }

    func wrapperSize() async -> String? {
        guard FileManager.default.fileExists(atPath: Paths.wrapper.path) else { return nil }
        let r = await CommandCapture.run(URL(fileURLWithPath: "/usr/bin/du"), ["-sh", Paths.wrapper.path])
        guard r.status == 0 else { return nil }
        return r.output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init)
    }

    private static func shellQuote(_ s: String) -> String {
        s.contains(where: { $0 == " " || $0 == "'" }) ? "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" : s
    }
}
