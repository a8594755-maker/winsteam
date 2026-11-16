import AppKit
import Foundation
import Observation

enum AppSection: Hashable {
    case games, status, troubleshoot
}

enum JobKind: Equatable {
    case setup(dryRun: Bool)
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

struct SetupProgress {
    var active = false
    var dryRun = false
    var currentStep = 0
    var succeeded: Bool?
    var failure: String?
}

struct LicensePrompt: Identifiable {
    let id = UUID()
    let text: String
}

/// 動作要開始前，GUI 需要先問使用者的事。
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    let action: () -> Void
}

@MainActor
@Observable
final class AppModel {
    var section: AppSection? = .status
    var report = DoctorReport.placeholder
    var checking = false
    var wrapper = WrapperState()
    var profiles: [GameProfile] = []
    let console = ConsoleModel()
    /// 一開始收合；執行任何指令時自動展開
    var consoleExpanded = false

    private(set) var job: Job?
    var setup = SetupProgress()
    var licensePrompt: LicensePrompt?
    var confirmation: PendingConfirmation?
    var showSetupConfirm = false
    var errorMessage: String?
    /// 已經按過「開始遊戲」的設定檔，顯示它們的小提醒
    var launchedProfiles: Set<String> = []
    /// 剛按下、還沒寫進 Info.plist 的值，讓控制項不會跳回舊值
    var pendingBackend: Backend?
    var pendingHUD: Bool?

    @ObservationIgnored private var runner: PTYProcess?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var licenseScanFrom = 0
    /// 這次指令輸出裡有 bash 本身的錯誤（CLI 的 --dry-run trap 可能讓它仍以 0 結束）
    @ObservationIgnored private var sawShellError = false
    /// setup 有印出最後的「✓ 安裝完成」
    @ObservationIgnored private var sawSetupDone = false
    @ObservationIgnored private var didChooseInitialSection = false

    var isBusy: Bool { job != nil }
    var installed: Bool { wrapper.installed }
    var cliAvailable: Bool { Paths.cli != nil }

    // MARK: 狀態

    func start() async {
        await refresh()
    }

    func reloadLocal() {
        wrapper = WrapperState.load()
        profiles = GameProfile.loadAll()
    }

    func refresh() async {
        reloadLocal()
        guard let cli = Paths.cli else {
            errorMessage = "找不到 winsteam 命令列工具。請用 app/scripts/bundle.sh 重新組裝 App。"
            return
        }
        checking = true
        let result = await CommandCapture.run(cli, ["doctor"])
        report = DoctorReport.parse(result.output)
        checking = false
        reloadLocal()
        if !didChooseInitialSection {
            didChooseInitialSection = true
            section = installed ? .games : .status
        }
    }

    /// 安裝前一定要通過的項目（setup 一開始就會檢查）
    var setupBlockers: [String] {
        var out: [String] = []
        if report.status(.appleSilicon) == .fail { out.append("這台 Mac 不是 Apple 晶片，無法使用。") }
        if report.status(.macOS) == .fail { out.append("需要 macOS 14 以上。") }
        if report.status(.homebrew) == .fail { out.append("需要先安裝 Homebrew（brew.sh），安裝 Homebrew 需要用到終端機。") }
        if report.status(.disk) == .fail, let d = report.items[.disk]?.detail { out.append(d) }
        return out
    }

    // MARK: 執行 CLI

    private func runCLI(_ args: [String], kind: JobKind, title: String,
                        completion: ((Int32) -> Void)? = nil) {
        guard job == nil else { return }
        guard let cli = Paths.cli else {
            errorMessage = "找不到 winsteam 命令列工具。"
            return
        }
        consoleExpanded = true
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
            sawSetupDone = false
        } catch {
            console.add("✗ 無法執行 winsteam：\(error.localizedDescription)", kind: .bad)
        }
    }

    private func handleOutput(_ text: String) {
        let lines = console.feed(text)
        if lines.contains(where: ConsoleModel.isShellError) { sawShellError = true }
        if case .setup = job?.kind {
            for line in lines { observeSetupLine(line) }
            checkLicensePrompt(idle: false)
            idleTask?.cancel()
            idleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.checkLicensePrompt(idle: true)
            }
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
        let finishedKind = job?.kind
        runner = nil
        job = nil
        licensePrompt = nil

        if case .setup(let dry) = finishedKind {
            setup.active = false
            if status == 0 && !sawSetupDone {
                status = 1
                setup.failure = "winsteam 沒有印出「安裝完成」就結束了，安裝可能沒有完成。詳細內容請看下方輸出。"
            }
            setup.succeeded = status == 0
            if status == 0 && !dry { setup.currentStep = 8 }
            if status != 0 && setup.failure == nil {
                setup.failure = "安裝在第 \(max(setup.currentStep, 1)) 步停下來了（代碼 \(status)）。詳細內容請看下方輸出。"
            }
        }
        completion?(status)
        pendingBackend = nil
        pendingHUD = nil
        Task { await refresh() }
    }

    func stop() {
        guard let runner else { return }
        console.add("（已要求停止）", kind: .note)
        runner.terminate()
    }

    // MARK: 安裝

    func startSetup(dryRun: Bool) {
        setup = SetupProgress(active: true, dryRun: dryRun, currentStep: 0, succeeded: nil, failure: nil)
        // 乾跑不需要 --yes（CLI 會自己略過確認）。真正安裝時，使用者已在 GUI 的確認視窗同意，
        // 所以加 --yes 回答 CLI 的「要安裝嗎？」。Apple 的 Rosetta 授權條款不在此列，另外詢問。
        let args = dryRun ? ["--dry-run", "setup"] : ["--yes", "setup"]
        runCLI(args, kind: .setup(dryRun: dryRun), title: dryRun ? "預演安裝" : "安裝中")
    }

    private func observeSetupLine(_ line: String) {
        if line.hasPrefix("▸ ") {
            let rest = line.dropFirst(2)
            if let slash = rest.firstIndex(of: "/"), let n = Int(rest[..<slash]) {
                setup.currentStep = n
            }
        } else if line.hasPrefix("✓") && line.contains("安裝完成") {
            sawSetupDone = true
        } else if line.hasPrefix("✗") || ConsoleModel.isShellError(line) {
            setup.failure = line.hasPrefix("✗") ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line
        }
    }

    // MARK: Rosetta 2 授權

    private static let licenseMarkers = [
        "type a", "type 'a'", "press return to agree", "agree to the terms",
        "software license agreement", "apple slas",
    ]

    /// 偵測 softwareupdate 的授權提示。WinSteam 絕不自動回答：只會跳出視窗，由使用者親自按「我同意」。
    private func checkLicensePrompt(idle: Bool) {
        guard case .setup(dryRun: false) = job?.kind, licensePrompt == nil else { return }
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
        // 不再重新偵測這一行（送出回答後它才會換行收進記錄）
        licenseScanFrom = console.nextID + (console.partial.isEmpty ? 0 : 1)
        licensePrompt = nil
        if agree {
            console.add("（你按下了「我同意」，WinSteam 把 A 送給 Apple 的安裝程式）", kind: .note)
            runner.write("A\n")
        } else {
            console.add("（你沒有同意 Apple 的授權條款，已停止安裝）", kind: .note)
            setup.failure = "你沒有同意 Rosetta 2 的授權條款，所以安裝停止了。沒有 Rosetta 2 無法執行 Windows 版 Steam。"
            runner.terminate()
        }
    }

    /// 備用方案：在「終端機」裡執行 Apple 的安裝程式，讓使用者直接看到原始提示並自己輸入。
    func installRosettaInTerminal() {
        if licensePrompt != nil {
            licensePrompt = nil
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
        echo "完成後可以關閉這個視窗，回到 WinSteam 按「重新檢查」，再按「開始安裝」。"
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

    // MARK: 啟動

    /// macOS 版 Steam 開著時，CLI 會問要不要先關掉；GUI 先問使用者，同意才加 --yes。
    private func withNativeSteamCheck(_ title: String, run: @escaping (_ yes: Bool) -> Void) {
        Task {
            let r = await CommandCapture.run(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-x", "steam_osx"])
            if r.status == 0 {
                confirmation = PendingConfirmation(
                    title: "macOS 版 Steam 正在執行",
                    message: "同一個帳號兩邊同時登入，Windows 版會顯示 NO CONNECTION。要先關閉 macOS 版 Steam，再\(title)嗎？",
                    confirmLabel: "關閉 macOS 版並繼續",
                    action: { run(true) })
            } else {
                run(false)
            }
        }
    }

    func openSteam() {
        withNativeSteamCheck("開啟 Steam") { [weak self] yes in
            self?.runCLI((yes ? ["--yes"] : []) + ["run"], kind: .openSteam, title: "開啟 Steam")
        }
    }

    func play(_ profile: GameProfile, backend: Backend?) {
        withNativeSteamCheck("開始遊戲") { [weak self] yes in
            var args = (yes ? ["--yes"] : []) + ["play", profile.id]
            if let backend { args += ["--backend", backend.rawValue] }
            self?.runCLI(args, kind: .play(profile.id), title: "啟動 \(profile.name)") { status in
                if status == 0 { self?.launchedProfiles.insert(profile.id) }
            }
        }
    }

    func dismissTips(_ profile: GameProfile) {
        launchedProfiles.remove(profile.id)
    }

    // MARK: 調校

    func setBackend(_ backend: Backend) {
        guard backend != wrapper.backend else { return }
        pendingBackend = backend
        runCLI(["backend", backend.rawValue], kind: .backend, title: "切換圖形後端")
    }

    func setHUD(_ on: Bool) {
        pendingHUD = on
        runCLI(["hud", on ? "on" : "off"], kind: .hud, title: on ? "開啟 Metal HUD" : "關閉 Metal HUD")
    }

    // MARK: 疑難排解

    func killWine() {
        runCLI(["kill"], kind: .kill, title: "結束 Wine 程序")
    }

    func showLogs() {
        runCLI(["logs"], kind: .logs, title: "查看記錄")
    }

    func showStatus() {
        runCLI(["status"], kind: .status, title: "目前設定")
    }

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
                self?.section = .status
            }
        }
    }

    func wrapperSize() async -> String? {
        guard FileManager.default.fileExists(atPath: Paths.wrapper.path) else { return nil }
        let r = await CommandCapture.run(URL(fileURLWithPath: "/usr/bin/du"), ["-sh", Paths.wrapper.path])
        guard r.status == 0 else { return nil }
        return r.output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init)
    }

    // MARK: 小工具

    private static func shellQuote(_ s: String) -> String {
        s.contains(where: { $0 == " " || $0 == "'" }) ? "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" : s
    }
}
