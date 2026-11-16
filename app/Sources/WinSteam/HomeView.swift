import SwiftUI

/// 首頁：任何時候只有一顆主要按鈕。
/// 還沒裝好 →「安裝」；安裝中 → 進度；出錯 →「重試」；裝好 → 每款遊戲一顆「開始遊戲」。
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.loaded {
                ProgressView().controlSize(.large)
            } else if model.setup.active {
                InstallingView()
            } else if model.setup.succeeded == false {
                InstallFailedView()
            } else if model.installed {
                GameListView()
            } else {
                WelcomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("WinSteam")
    }
}

/// 置中的單欄版面
private struct CenteredPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 18) { content }
                .frame(maxWidth: 460)
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }
}

private struct HeroIcon: View {
    var symbol = "gamecontroller.fill"
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 84, height: 84)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tint.gradient))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

// MARK: - 還沒安裝

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CenteredPage {
            HeroIcon()
            Text("在 Mac 上玩 Windows 遊戲").font(.largeTitle.weight(.semibold))
            Text(model.wrapper.partiallyInstalled
                 ? "上次的安裝沒有完成。按「繼續安裝」，WinSteam 會從停下來的地方接著做。"
                 : "WinSteam 會幫你裝好 Windows 版 Steam。裝好之後用你自己的帳號登入，就能玩 Steam 上的 Windows 遊戲。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button { model.install() } label: {
                Text(model.wrapper.partiallyInstalled ? "繼續安裝" : "安裝")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 180)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            // 不綁 Return：安裝會下載與安裝軟體，不該被誤按的按鍵觸發
            .disabled(model.isBusy || !model.cliAvailable)
            .padding(.top, 6)

            Text("需要網路，約十幾分鐘。過程中會下載 Wine 相容元件與 Windows 版 Steam，並用 Homebrew 安裝開源工具 Sikarugir（未經 Apple 公證）。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 安裝中

private struct InstallingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.setup
        CenteredPage {
            HeroIcon(symbol: "arrow.down")
            Text("正在安裝").font(.largeTitle.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: s.fraction)
                    .animation(.easeInOut, value: s.fraction)
                Text(s.message)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if s.wizardFallback {
                Label {
                    Text("Steam 的安裝視窗會跳出來，需要你點一下：安裝路徑保持預設；最後一頁先取消勾選「Run Steam」，再按 Finish。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }

            Text("可以先去做別的事，裝好後 Steam 會自己開啟。")
                .font(.callout)
                .foregroundStyle(.secondary)

            DetailsDisclosure()
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("停止安裝") { model.stop() }
                .controlSize(.regular)
        }
    }
}

// MARK: - 出錯

private struct InstallFailedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        CenteredPage {
            HeroIcon(symbol: "exclamationmark.triangle.fill", tint: .orange)
            Text("安裝沒有完成").font(.largeTitle.weight(.semibold))
            Text(model.setup.failure ?? "發生了問題。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button { model.install() } label: {
                Text("重試")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 180)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(model.isBusy)
            .padding(.top, 6)

            Text("已經完成的部分不會重做。").font(.footnote).foregroundStyle(.tertiary)

            DetailsDisclosure(title: "詳細資訊")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 已安裝：遊戲清單

private struct GameListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.justInstalled {
                    LoginBanner()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("遊戲").font(.largeTitle.weight(.semibold))
                    Text("遊戲要先在 Steam 裡用你的帳號安裝好，再回來按「開始遊戲」。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.profiles.isEmpty {
                    Card { Text("目前沒有支援的遊戲。").foregroundStyle(.secondary) }
                } else {
                    ForEach(model.profiles) { GameRow(profile: $0) }
                }

                HStack(spacing: 4) {
                    Text("要登入或在 Steam 安裝遊戲？")
                    Button("開啟 Steam") { model.openSteam() }
                        .buttonStyle(.link)
                        .disabled(model.isBusy)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LoginBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("裝好了！請在 Steam 視窗登入你的帳號").font(.headline)
                Text("第一次開啟會先下載更新，視窗看起來像沒反應是正常的，等幾分鐘就好。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { model.justInstalled = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("關閉")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green.opacity(0.3)))
    }
}

private struct GameRow: View {
    @Environment(AppModel.self) private var model
    let profile: GameProfile

    private var isLaunching: Bool { model.job?.kind == .play(profile.id) }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(profile.experimental ? Color.orange.gradient : Color.accentColor.gradient))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(profile.name).font(.title3.weight(.semibold))
                            if profile.experimental {
                                Badge(text: "實驗性").help("還沒確認能在 Mac 上順利玩")
                            }
                        }
                        if profile.experimental {
                            Text("還沒確認能在 Mac 上順利玩").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Button { model.play(profile) } label: {
                        HStack(spacing: 6) {
                            if isLaunching { ProgressView().controlSize(.small) }
                            Text("開始遊戲").fontWeight(.semibold)
                        }
                        .frame(minWidth: 96)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                }

                if model.launchedProfiles.contains(profile.id) {
                    LaunchedTips(profile: profile)
                }
            }
        }
    }
}

private struct LaunchedTips: View {
    @Environment(AppModel.self) private var model
    let profile: GameProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("已請 Steam 開啟 \(profile.name)，可能要等一下。").font(.callout.weight(.semibold))
                Spacer()
                Button { model.dismissTips(profile) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("關閉")
            }
            ForEach(profile.tips, id: \.self) { tip in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundStyle(.yellow)
                    Text(tip).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
            if let alt = profile.backendAlt {
                Button("打不開或畫面怪怪的？換另一種模式再試一次") { model.play(profile, backend: alt) }
                    .buttonStyle(.link)
                    .font(.callout)
                    .disabled(model.isBusy)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
