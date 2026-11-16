import SwiftUI

struct TroubleshootView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmKill = false
    @State private var showUninstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "疑難排解",
                           subtitle: "遊戲或 Steam 卡住、出現奇怪的錯誤時，可以從這裡處理。執行結果會顯示在下方的輸出面板。")

                ActionRow(symbol: "xmark.octagon", tint: .orange,
                          title: "結束卡住的程序",
                          detail: "Steam 或遊戲沒有反應、關不掉時使用。會強制結束這個 wrapper 裡所有 Wine 程序，未存檔的進度會遺失。") {
                    Button("強制結束") { confirmKill = true }
                        .disabled(model.isBusy || !model.wrapper.hasWrapper)
                }

                ActionRow(symbol: "doc.text.magnifyingglass", tint: .accentColor,
                          title: "查看記錄",
                          detail: "顯示 Steam 記錄檔的最後幾行。回報問題時可以把輸出面板的內容拷貝給別人看。") {
                    HStack {
                        Button("在 Finder 中顯示") { model.revealLogs() }
                            .disabled(!model.wrapper.hasWrapper)
                        Button("顯示記錄") { model.showLogs() }
                            .disabled(model.isBusy || !model.wrapper.hasWrapper)
                    }
                }

                ActionRow(symbol: "slider.horizontal.3", tint: .accentColor,
                          title: "目前設定",
                          detail: "顯示 wrapper 的位置、Wine 引擎版本、圖形後端與同步設定。") {
                    Button("顯示設定") { model.showStatus() }
                        .disabled(model.isBusy || !model.wrapper.hasWrapper)
                }

                ActionRow(symbol: "trash", tint: .red,
                          title: "移除 Windows 版 Steam",
                          detail: "刪除 wrapper，裡面的 Windows 版 Steam 和所有已下載的遊戲都會一起刪掉，無法復原。") {
                    Button("移除…", role: .destructive) { showUninstall = true }
                        .disabled(model.isBusy || !FileManager.default.fileExists(atPath: Paths.wrapper.path))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Wrapper 位置").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Paths.wrapper.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(.top, 6)
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("要強制結束所有 Wine 程序嗎？", isPresented: $confirmKill) {
            Button("強制結束", role: .destructive) { model.killWine() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Steam 和正在執行的遊戲都會被關掉，未存檔的進度會遺失。")
        }
        .sheet(isPresented: $showUninstall) { UninstallSheet() }
    }
}

private struct ActionRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                trailing.controlSize(.large)
            }
        }
    }
}

/// 明確的破壞性確認
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
                Label {
                    Text(Paths.wrapper.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                } icon: { Image(systemName: "folder") }
                Text(size.map { "目前佔用約 \($0)。" } ?? "正在計算佔用空間…")
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))

            Toggle(isOn: $alsoDownloads) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("同時刪除下載的 Wine 引擎、範本與 Steam 安裝檔")
                    Text("之後重新安裝時要再下載一次。Sikarugir Creator 和 Rosetta 2 不會被刪除。")
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
        .frame(width: 560)
        .task { size = await model.wrapperSize() }
    }
}
