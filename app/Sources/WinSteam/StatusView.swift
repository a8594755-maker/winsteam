import SwiftUI

struct StatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "安裝與狀態",
                    subtitle: model.installed
                        ? "Windows 版 Steam 已經裝好，可以到「遊戲」開始玩。"
                        : "WinSteam 會一步一步幫你裝好 Windows 版 Steam。需要你動手的地方會用橘色標出來。")

                if model.report.nativeSteamRunning {
                    Callout(style: .info, title: "macOS 版 Steam 正在執行",
                            message: "同一個帳號兩邊同時登入，Windows 版會顯示 NO CONNECTION。開始遊戲前 WinSteam 會問你要不要先關掉它。")
                }

                ChecksSection()
                InstallSection()
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 環境檢查

private struct ChecksSection: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top),
                           GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("環境檢查").font(.title2.weight(.semibold))
                if model.checking { ProgressView().controlSize(.small) }
                Spacer()
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CheckKey.allCases) { key in
                    CheckRow(item: model.report.items[key]
                             ?? CheckItem(key: key, status: .unknown, detail: "檢查中…"))
                }
            }
        }
    }
}

private struct CheckRow: View {
    let item: CheckItem

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.key.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.key.title).font(.headline)
                    Text(item.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 4)
                StatusIcon(status: item.status)
            }
        }
    }
}

struct StatusIcon: View {
    let status: CheckStatus

    var body: some View {
        Group {
            switch status {
            case .pass: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .fail: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .missing: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            case .unknown: ProgressView().controlSize(.small)
            }
        }
        .font(.title3)
        .help(helpText)
    }

    private var helpText: String {
        switch status {
        case .pass: "通過"
        case .warn: "要注意"
        case .fail: "未通過"
        case .missing: "尚未安裝"
        case .unknown: "檢查中"
        }
    }
}

// MARK: - 安裝

private struct InstallSection: View {
    @Environment(AppModel.self) private var model

    private var setupRunning: Bool {
        if case .setup = model.job?.kind { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("安裝").font(.title2.weight(.semibold))

            if model.installed && !setupRunning && model.setup.succeeded == nil {
                InstalledSummary()
            } else {
                SetupStatusBanner()
                if !setupRunning { SetupButtons() }
                Card { SetupStepList() }
            }
        }
    }
}

private struct InstalledSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Windows 版 Steam 已經裝好了", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                Text("如果還沒登入，按「開啟 Steam」後在 Steam 視窗用你自己的帳號登入。第一次開啟會下載更新，視窗看起來像當掉是正常的，等幾分鐘。")
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { model.section = .games } label: {
                        Label("前往遊戲", systemImage: "gamecontroller")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button { model.openSteam() } label: {
                        Label("開啟 Steam", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                    .disabled(model.isBusy)
                    Spacer()
                    Button("重新執行安裝") { model.showSetupConfirm = true }
                        .help("會略過已經完成的步驟，只補上缺少的部分")
                        .disabled(model.isBusy)
                }
            }
        }
    }
}

/// 安裝中／完成／失敗時最上方的大提示
private struct SetupStatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.setup
        if s.active {
            let step = SetupStep.all.first { $0.number == s.currentStep }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(step.map { "第 \($0.number) 步，共 7 步：\($0.title)" } ?? "準備中…")
                        .font(.headline)
                    if s.dryRun { Badge(text: "預演", tint: .accentColor) }
                    Spacer()
                    Button(role: .destructive) { model.stop() } label: { Text("停止") }
                }
                if let step, let action = step.userAction, !s.dryRun {
                    Callout(style: .action, title: "現在需要你：", message: action)
                }
            }
        } else if s.succeeded == true && s.dryRun {
            Callout(style: .info, title: "預演結束",
                    message: "上面的步驟都只是預演，沒有下載、安裝或修改任何東西。準備好了就按「開始安裝」。")
        } else if s.succeeded == true {
            VStack(alignment: .leading, spacing: 10) {
                Callout(style: .success, title: "安裝完成！接下來還有幾件事要你自己做：",
                        lines: [
                            "按「開啟 Steam」，在 Steam 視窗用你自己的帳號登入。",
                            "第一次開啟會下載更新，視窗看起來像當掉是正常的，請等幾分鐘。",
                            "在 Steam 的「設定 → 介面」關掉「在網頁檢視中啟用 GPU 加速算繪」。",
                            "在 Steam 裡安裝遊戲，再回到 WinSteam 的「遊戲」開始玩。",
                        ])
                HStack {
                    Button { model.openSteam() } label: { Label("開啟 Steam", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isBusy)
                    Button("前往遊戲") { model.section = .games }
                        .controlSize(.large)
                }
            }
        } else if s.succeeded == false {
            Callout(style: .failure, title: s.dryRun ? "預演時發現問題" : "安裝沒有完成",
                    message: s.failure ?? "詳細內容請看下方輸出。")
        }
    }
}

private struct SetupStepList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SetupStep.all) { step in
                StepRow(step: step, state: state(for: step))
                Divider().padding(.leading, 40)
            }
            StepRow(step: SetupStep(number: 8, title: "登入 Steam",
                                    detail: "安裝完成後開啟 Steam，用你自己的帳號登入。",
                                    userAction: "WinSteam 不會碰你的帳號密碼，登入要你自己在 Steam 視窗完成。"),
                    state: model.installed ? .done : (model.setup.currentStep == 8 ? .current : .pending))
        }
    }

    private func state(for step: SetupStep) -> StepRow.State {
        let s = model.setup
        // 預演跑完後不把步驟標成完成（實際上什麼都沒做）
        if s.active || (s.succeeded != nil && !(s.dryRun && s.succeeded == true)) {
            if s.succeeded == true && !s.active { return .done }
            if step.number < s.currentStep { return .done }
            if step.number == s.currentStep { return s.succeeded == false ? .failed : .current }
            return .pending
        }
        // 還沒開始：用環境檢查推測哪些步驟已經完成
        let r = model.report
        let basicsPass = [CheckKey.appleSilicon, .macOS, .homebrew, .disk].allSatisfy { r.status($0) == .pass }
        switch step.number {
        case 1 where basicsPass: return .done
        case 2 where r.status(.rosetta) == .pass: return .done
        case 3 where r.status(.creator) == .pass: return .done
        case 5 where r.status(.wrapper) == .pass: return .done
        case 6 where r.status(.steam) == .pass: return .done
        default: return .pending
        }
    }
}

private struct StepRow: View {
    enum State { case pending, current, done, failed }
    let step: SetupStep
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(step.number <= 7 ? "\(step.number). \(step.title)" : step.title)
                        .font(.headline)
                        .foregroundStyle(state == .pending ? .secondary : .primary)
                    if step.userAction != nil { Badge(text: "需要你動手") }
                }
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = step.userAction {
                    Label(action, systemImage: "hand.point.right")
                        .font(.callout)
                        .foregroundStyle(state == .current ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .background(state == .current ? Color.accentColor.opacity(0.06) : .clear)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary).font(.title3)
        case .current: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.title3)
        }
    }
}

private struct SetupButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let blockers = model.setupBlockers
        VStack(alignment: .leading, spacing: 10) {
            if !blockers.isEmpty {
                Callout(style: .failure, title: "要先處理這些項目才能安裝", lines: blockers)
                if model.report.status(.homebrew) == .fail {
                    Link("開啟 brew.sh（Homebrew 官方網站）", destination: URL(string: "https://brew.sh")!)
                }
            }
            HStack(spacing: 10) {
                Button { model.showSetupConfirm = true } label: {
                    Label(model.setup.succeeded == false ? "再試一次" : "開始安裝", systemImage: "arrow.down.circle.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || !blockers.isEmpty || model.checking || !model.cliAvailable)

                Button("預演一次（不會改動任何東西）") { model.startSetup(dryRun: true) }
                    .controlSize(.large)
                    .disabled(model.isBusy || !model.cliAvailable)
                Spacer()
            }
            if model.report.status(.rosetta) == .fail {
                HStack(spacing: 4) {
                    Text("Rosetta 2 的授權條款會在安裝時出現在 WinSteam 裡。如果一直沒有出現，也可以")
                    Button("改用終端機安裝 Rosetta 2") { model.installRosettaInTerminal() }
                        .buttonStyle(.link)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 安裝前的確認

struct SetupConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = model.report
        VStack(alignment: .leading, spacing: 16) {
            Label("開始安裝 Windows 版 Steam", systemImage: "arrow.down.circle.fill")
                .font(.title2.weight(.semibold))
            Text("WinSteam 會依序做下面這些事。按「開始安裝」代表你同意讓 WinSteam 代你回答安裝程式的「要繼續嗎？」問題。")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                if r.status(.rosetta) != .pass {
                    bullet("arrow.triangle.2.circlepath",
                           "安裝 Apple 的 Rosetta 2。Apple 的授權條款會另外跳出來，由你自己決定是否同意，WinSteam 不會替你按。")
                }
                if r.status(.creator) != .pass {
                    bullet("hammer",
                           "用 Homebrew 安裝 Sikarugir Creator。它沒有經過 Apple 公證（ad-hoc 簽章），Homebrew 安裝時會移除隔離標記。")
                }
                bullet("arrow.down.doc",
                       "從 GitHub 下載 Wine 引擎與 wrapper 範本，從 Steam 官方網站下載安裝程式。已下載過的會略過。")
                bullet("hand.raised",
                       "Steam 的安裝精靈跳出來時要你自己點：安裝路徑保持預設；最後一頁取消勾選「Run Steam」再按 Finish。")
                bullet("person.crop.circle",
                       "裝好之後，你要自己開啟 Steam 並登入帳號。")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            Text("需要的時間取決於網路速度，通常是幾分鐘到十幾分鐘。過程中可以隨時按「停止」。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("開始安裝") {
                    dismiss()
                    model.startSetup(dryRun: false)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Rosetta 2 授權

struct LicenseSheet: View {
    @Environment(AppModel.self) private var model
    let prompt: LicensePrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Apple 需要你同意 Rosetta 2 的授權條款", systemImage: "doc.text.magnifyingglass")
                .font(.title2.weight(.semibold))
            Text("下面是 Apple 安裝程式顯示的原文。請自己閱讀並決定是否同意。WinSteam 不會替你同意：只有在你按下「我同意」之後，才會把你的回答（A）送給 Apple 的安裝程式。")
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(prompt.text.isEmpty ? "（安裝程式正在等待回答，但沒有顯示文字。）" : prompt.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 110, maxHeight: 220)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))

            Link("在瀏覽器開啟 Apple 的軟體授權條款（apple.com/legal/sla）",
                 destination: URL(string: "https://www.apple.com/legal/sla/")!)

            HStack {
                Button("改用終端機") { model.installRosettaInTerminal() }
                    .help("停止這次安裝，改在「終端機」裡看 Apple 的原始提示並自己輸入")
                Spacer()
                Button("不同意（停止安裝）", role: .destructive) { model.answerLicense(agree: false) }
                    .keyboardShortcut(.cancelAction)
                Button("我同意") { model.answerLicense(agree: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled()
    }
}
