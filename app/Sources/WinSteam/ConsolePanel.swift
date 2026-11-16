import AppKit
import SwiftUI

/// 可收合的即時輸出面板，顯示 CLI 的 stdout / stderr。
struct ConsolePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
            if model.consoleExpanded {
                Divider()
                ConsoleLog(console: model.console)
                    .frame(height: 210)
            }
        }
        .background(.bar)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.consoleExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(model.consoleExpanded ? 90 : 0))
                        .font(.caption.weight(.bold))
                    Image(systemName: "terminal")
                    Text("輸出").font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.consoleExpanded ? "收合輸出（⌘J）" : "展開輸出（⌘J）")

            if let job = model.job {
                ProgressView().controlSize(.small)
                Text(job.title).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.isBusy {
                Button("停止") { model.stop() }
                    .controlSize(.small)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.console.plainText, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("拷貝全部輸出")
                .disabled(model.console.lines.isEmpty)
            Button { model.console.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("清除輸出")
                .disabled(model.console.lines.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct ConsoleLog: View {
    let console: ConsoleModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if console.lines.isEmpty && console.partial.isEmpty {
                        Text("這裡會顯示 winsteam 的即時輸出。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(console.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .foregroundStyle(color(line.kind))
                            .fontWeight(line.kind == .step || line.kind == .command ? .semibold : .regular)
                            .padding(.top, line.kind == .command ? 6 : 0)
                    }
                    if !console.partial.isEmpty {
                        Text(console.partial).foregroundStyle(.primary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
