import SwiftUI

/// 一個視窗、一個首頁；其他東西都在第二層的「進階」。
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .advanced: AdvancedView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.path = [.advanced] } label: {
                            Label("進階", systemImage: "gearshape")
                        }
                        .help("環境檢查、圖形設定、記錄與移除")
                    }
                }
        }
        .sheet(item: $model.licensePrompt) { LicenseSheet(prompt: $0) }
        .alert(item: $model.confirmation) { c in
            Alert(title: Text(c.title), message: Text(c.message),
                  primaryButton: .default(Text(c.confirmLabel), action: c.action),
                  secondaryButton: .cancel(Text("取消")))
        }
        .alert("沒有成功", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - 共用元件

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

struct Badge: View {
    let text: String
    var tint: Color = .orange

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// 可展開的原始輸出（安裝畫面、錯誤畫面用）
struct DetailsDisclosure: View {
    @Environment(AppModel.self) private var model
    var title = "顯示詳細過程"
    @State private var expanded = false

    var body: some View {
        // 不用 DisclosureGroup：macOS 上只有小三角形能點，整行文字點了沒反應
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(expanded ? "隱藏" + title.replacingOccurrences(of: "顯示", with: "") : title)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ConsoleLog(console: model.console)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            }
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
            Text("Rosetta 2 是 Apple 的元件，玩 Windows 遊戲一定要有。下面是 Apple 安裝程式顯示的原文，請自己閱讀並決定。WinSteam 不會替你同意：只有你按下「我同意」，才會把回答（A）送給 Apple 的安裝程式。")
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(prompt.text.isEmpty ? "（安裝程式正在等待回答，但沒有顯示文字。）" : prompt.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 100, maxHeight: 200)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))

            Link("在瀏覽器閱讀 Apple 的軟體授權條款",
                 destination: URL(string: "https://www.apple.com/legal/sla/")!)

            HStack {
                Button("改用終端機") { model.installRosettaInTerminal() }
                    .help("停止這次安裝，改在「終端機」裡看 Apple 的原始提示並自己輸入")
                Spacer()
                Button("不同意") { model.answerLicense(agree: false) }
                    .keyboardShortcut(.cancelAction)
                Button("我同意") { model.answerLicense(agree: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled()
    }
}
