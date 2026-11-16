import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.section) {
                Label("遊戲", systemImage: "gamecontroller").tag(AppSection.games)
                Label("安裝與狀態", systemImage: "checklist").tag(AppSection.status)
                Label("疑難排解", systemImage: "wrench.and.screwdriver").tag(AppSection.troubleshoot)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarStatus().padding(12) }
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch model.section ?? .status {
                    case .games: GamesView()
                    case .status: StatusView()
                    case .troubleshoot: TroubleshootView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                ConsolePanel()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.checking {
                    ProgressView().controlSize(.small).padding(.horizontal, 6)
                } else {
                    Button { Task { await model.refresh() } } label: {
                        Label("重新檢查", systemImage: "arrow.clockwise")
                    }
                    .help("重新檢查安裝狀態（⌘R）")
                }
            }
        }
        .sheet(item: $model.licensePrompt) { prompt in
            LicenseSheet(prompt: prompt)
        }
        .sheet(isPresented: $model.showSetupConfirm) {
            SetupConfirmSheet()
        }
        .alert(item: $model.confirmation) { c in
            Alert(title: Text(c.title), message: Text(c.message),
                  primaryButton: .default(Text(c.confirmLabel), action: c.action),
                  secondaryButton: .cancel(Text("取消")))
        }
        .alert("發生問題", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// 側欄底部的小狀態
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if let job = model.job {
                ProgressView().controlSize(.small)
                Text(job.title).lineLimit(1)
            } else if model.installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Steam 已就緒")
            } else {
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                Text("尚未安裝完成")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
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
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
            )
    }
}

/// 彩色提示框（需要使用者動手、成功、失敗…）
struct Callout: View {
    enum Style { case action, success, failure, info }
    let style: Style
    let title: String
    var message: String? = nil
    var lines: [String] = []

    private var tint: Color {
        switch style {
        case .action: .orange
        case .success: .green
        case .failure: .red
        case .info: .accentColor
        }
    }

    private var symbol: String {
        switch style {
        case .action: "hand.raised.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                if let message {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.35)))
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

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
