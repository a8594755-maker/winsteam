import AppKit
import SwiftUI

/// 第二層：一般使用者不需要的東西都在這裡。
struct AdvancedView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmKill = false
    @State private var showUninstall = false

    private var hasWrapper: Bool { model.wrapper.hasWrapper }

    var body: some View {
        Form {
            Section {
                ForEach(CheckKey.allCases) { key in
                    let item = model.report.items[key] ?? CheckItem(key: key, status: .unknown, detail: "")
                    LabeledContent {
                        StatusIcon(status: item.status)
                    } label: {
                        Text(key.title)
                        Text(item.detail).lineLimit(2).truncationMode(.middle)
                    }
                }
            } header: {
                HStack {
                    Text("這台 Mac")
                    Spacer()
                    if model.checking { ProgressView().controlSize(.small) }
                    Button("重新檢查") { Task { await model.refresh() } }
                        .buttonStyle(.link)
                        .disabled(model.checking)
                }
            }

            Section {
                Picker("圖形後端", selection: Binding(
                    get: { model.pendingBackend ?? model.wrapper.backend },
                    set: { model.setBackend($0) })
                ) {
                    ForEach(Backend.allCases) { Text($0.displayName).tag($0) }
                }
                .disabled(model.isBusy || !hasWrapper)
                Toggle("Metal 效能 HUD（顯示 FPS）", isOn: Binding(
                    get: { model.pendingHUD ?? model.wrapper.hud ?? false },
                    set: { model.setHUD($0) })
                )
                .disabled(model.isBusy || model.wrapper.hud == nil)
            } header: {
                Text("圖形")
            } footer: {
                Text("\((model.pendingBackend ?? model.wrapper.backend).summary)開始遊戲時會改用該遊戲的建議設定；這裡的設定影響直接開啟 Steam 的情況。改完後下次啟動生效。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("工具") {
                ToolRow(title: "開啟 Steam", detail: "用來登入、安裝或管理遊戲。") {
                    Button("開啟") { model.openSteam() }.disabled(model.isBusy || !model.installed)
                }
                ToolRow(title: "結束卡住的程序", detail: "Steam 或遊戲沒有反應時使用，未存檔的進度會遺失。") {
                    Button("強制結束") { confirmKill = true }.disabled(model.isBusy || !hasWrapper)
                }
                ToolRow(title: "Steam 記錄檔", detail: "回報問題時用。") {
                    HStack {
                        Button("在 Finder 顯示") { model.revealLogs() }.disabled(!hasWrapper)
                        Button("顯示") { model.showLogs() }.disabled(model.isBusy || !hasWrapper)
                    }
                }
                ToolRow(title: "目前設定", detail: "wrapper 位置、引擎版本、後端與同步設定。") {
                    Button("顯示") { model.showStatus() }.disabled(model.isBusy || !hasWrapper)
                }
                ToolRow(title: "重新執行安裝", detail: "修復裝壞的地方，已完成的步驟會略過。") {
                    Button("執行") { model.path = []; model.install() }.disabled(model.isBusy)
                }
                ToolRow(title: "預演安裝", detail: "只顯示安裝會做什麼，不會改動任何東西。") {
                    Button("預演") { model.dryRun() }.disabled(model.isBusy)
                }
                if model.report.status(.rosetta) == .fail {
                    ToolRow(title: "用終端機安裝 Rosetta 2", detail: "安裝時如果沒有出現 Apple 的授權條款，可以改用這個。") {
                        Button("開啟終端機") { model.installRosettaInTerminal() }
                    }
                }
            }

            Section {
                ConsoleLog(console: model.console)
                    .frame(height: 220)
            } header: {
                HStack {
                    Text("輸出")
                    if let job = model.job {
                        ProgressView().controlSize(.small)
                        Text(job.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isBusy { Button("停止") { model.stop() }.buttonStyle(.link) }
                    Button("拷貝") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.console.plainText, forType: .string)
                    }
                    .buttonStyle(.link)
                    .disabled(model.console.lines.isEmpty)
                    Button("清除") { model.console.clear() }
                        .buttonStyle(.link)
                        .disabled(model.console.lines.isEmpty || model.isBusy)
                }
            }

            Section {
                ToolRow(title: "移除 Windows 版 Steam", detail: "Steam 和所有已下載的遊戲都會刪掉，無法復原。") {
                    Button("移除…", role: .destructive) { showUninstall = true }
                        .disabled(model.isBusy || !FileManager.default.fileExists(atPath: Paths.wrapper.path))
                }
            } footer: {
                Text(Paths.wrapper.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("進階")
        .alert("要強制結束所有 Wine 程序嗎？", isPresented: $confirmKill) {
            Button("強制結束", role: .destructive) { model.killWine() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Steam 和正在執行的遊戲都會被關掉，未存檔的進度會遺失。")
        }
        .sheet(isPresented: $showUninstall) { UninstallSheet() }
    }
}

private struct ToolRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

struct StatusIcon: View {
    let status: CheckStatus

    var body: some View {
        switch status {
        case .pass: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("通過")
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("要注意")
        case .fail: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("未通過")
        case .missing: Image(systemName: "circle.dashed").foregroundStyle(.secondary).help("尚未安裝")
        case .unknown: ProgressView().controlSize(.small)
        }
    }
}

// MARK: - 輸出

struct ConsoleLog: View {
    let console: ConsoleModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if console.lines.isEmpty && console.partial.isEmpty {
                        Text("這裡會顯示 winsteam 的即時輸出。").foregroundStyle(.secondary)
                    }
                    ForEach(console.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .foregroundStyle(color(line.kind))
                            .fontWeight(line.kind == .step || line.kind == .command ? .semibold : .regular)
                            .padding(.top, line.kind == .command ? 6 : 0)
                    }
                    if !console.partial.isEmpty {
                        Text(console.partial)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: console.nextID) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: console.partial) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func color(_ kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .ok: .green
        case .warn: .orange
        case .bad: .red
        case .step, .plain: .primary
        case .dim, .note: .secondary
        case .command: .accentColor
        }
    }
}

// MARK: - 移除（明確的破壞性確認）

private struct UninstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var alsoDownloads = false
    @State private var size: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text("確定要移除 Windows 版 Steam 嗎？").font(.title2.weight(.semibold))
                    Text("這個動作無法復原。").font(.headline).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("會刪除：").font(.headline)
                Label("Windows 版 Steam 本身", systemImage: "minus.circle")
                Label("所有已經下載、安裝在裡面的遊戲，以及存在這台 Mac 上的遊戲資料", systemImage: "minus.circle")
                Text(size.map { "目前佔用約 \($0)。" } ?? "正在計算佔用空間…")
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))

            Toggle(isOn: $alsoDownloads) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同時刪除下載的安裝檔")
                    Text("之後重新安裝要再下載一次。Sikarugir 和 Rosetta 2 不會被刪除。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("你在 Steam 帳號裡買的遊戲不會消失，之後重新安裝再下載即可。")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button(role: .destructive) {
                    dismiss()
                    model.path = []
                    model.uninstall(all: alsoDownloads)
                } label: {
                    Text("刪除 Steam 與所有遊戲")
                }
                .controlSize(.large)
                .tint(.red)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { size = await model.wrapperSize() }
    }
}
