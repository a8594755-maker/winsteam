import SwiftUI

struct GamesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.installed {
            ContentUnavailableView {
                Label("Windows 版 Steam 還沒裝好", systemImage: "gamecontroller")
            } description: {
                Text("先到「安裝與狀態」完成安裝，再回來這裡開始遊戲。")
            } actions: {
                Button("前往安裝") { model.section = .status }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(title: "遊戲",
                               subtitle: "遊戲要先在 Steam 裡用你自己的帳號買好並安裝。WinSteam 會套用每款遊戲的建議設定再啟動。")
                    SteamCard()
                    Text("遊戲設定檔").font(.title2.weight(.semibold))
                    if model.profiles.isEmpty {
                        Card { Text("找不到任何遊戲設定檔（profiles/*.conf）。").foregroundStyle(.secondary) }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(model.profiles) { GameCard(profile: $0) }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Steam 與全域設定

private struct SteamCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Windows 版 Steam").font(.title3.weight(.semibold))
                        Text("在 Steam 視窗裡登入、安裝與管理遊戲。第一次開啟會先下載更新。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { model.openSteam() } label: {
                        Label("開啟 Steam", systemImage: "play.fill").padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                }

                Divider()

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("圖形後端", selection: Binding(
                            get: { model.pendingBackend ?? model.wrapper.backend },
                            set: { model.setBackend($0) })
                        ) {
                            ForEach(Backend.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(model.isBusy)
                        Text((model.pendingBackend ?? model.wrapper.backend).summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Metal 效能 HUD", isOn: Binding(
                            get: { model.pendingHUD ?? model.wrapper.hud ?? false },
                            set: { model.setHUD($0) })
                        )
                        .toggleStyle(.switch)
                        .disabled(model.isBusy || model.wrapper.hud == nil)
                        Text(model.wrapper.hud == nil
                             ? "這個 wrapper 範本不支援從這裡切換 HUD。"
                             : "在畫面角落顯示 FPS 與畫格時間，用來判斷順不順。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label("圖形後端和 HUD 是整個 Steam 共用的設定，改完後下次啟動 Steam 或遊戲時生效。",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 遊戲卡片

private struct GameCard: View {
    @Environment(AppModel.self) private var model
    let profile: GameProfile
    /// nil = 用設定檔的預設後端
    @State private var choice: Backend?

    private var isLaunching: Bool { model.job?.kind == .play(profile.id) }

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(profile.experimental ? Color.orange.gradient : Color.accentColor.gradient))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(profile.name).font(.title3.weight(.semibold))
                            if profile.experimental { Badge(text: "實驗性") }
                        }
                        if let appID = profile.appID {
                            Text("App ID \(appID)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !profile.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(profile.notes, id: \.self) {
                            Text($0).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("建議後端").foregroundStyle(.secondary)
                        Text(profile.backend?.displayName ?? "未指定")
                    }
                    if let alt = profile.backendAlt {
                        GridRow {
                            Text("備用後端").foregroundStyle(.secondary)
                            Text(alt.displayName)
                        }
                    }
                    GridRow {
                        Text("目前設定").foregroundStyle(.secondary)
                        Text(model.wrapper.backend.displayName)
                    }
                }
                .font(.callout)

                Picker("這次使用", selection: $choice) {
                    Text("建議（\(profile.backend?.displayName ?? "不變")）").tag(Backend?.none)
                    Divider()
                    ForEach(Backend.allCases) { b in
                        Text(b == profile.backendAlt ? "\(b.displayName)（備用）" : b.displayName).tag(Backend?.some(b))
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isBusy)

                Button {
                    model.play(profile, backend: choice == profile.backend ? nil : choice)
                } label: {
                    HStack {
                        if isLaunching { ProgressView().controlSize(.small) }
                        Label("開始遊戲", systemImage: "play.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy)

                if model.launchedProfiles.contains(profile.id) {
                    TipsBox(profile: profile, onRetry: { alt in
                        choice = alt
                        model.play(profile, backend: alt)
                    })
                }
            }
        }
    }
}

private struct TipsBox: View {
    @Environment(AppModel.self) private var model
    let profile: GameProfile
    let onRetry: (Backend) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("已要求 Steam 啟動 \(profile.name)", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Button { model.dismissTips(profile) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("關閉小提醒")
            }
            if !profile.tips.isEmpty {
                Text("小提醒").font(.subheadline.weight(.semibold)).padding(.top, 2)
                ForEach(profile.tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "lightbulb").foregroundStyle(.yellow)
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
            }
            if let alt = profile.backendAlt {
                Button("畫面異常或起不來？改用 \(alt.displayName) 再試一次") { onRetry(alt) }
                    .buttonStyle(.link)
                    .font(.callout)
                    .disabled(model.isBusy)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.green.opacity(0.3)))
    }
}
