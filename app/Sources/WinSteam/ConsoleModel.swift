import Foundation
import Observation

struct ConsoleLine: Identifiable, Equatable {
    enum Kind { case plain, ok, warn, bad, step, dim, command, note }
    let id: Int
    let text: String
    let kind: Kind
}

/// 即時輸出面板的內容。處理 ANSI 色碼、pty 的 \r\n，以及 curl 進度列用的單獨 \r（覆寫同一行）。
@Observable
final class ConsoleModel {
    private(set) var lines: [ConsoleLine] = []
    /// 還沒換行的那一段（例如等待輸入的提示），原始文字
    private(set) var partialRaw = ""
    private(set) var nextID = 0
    @ObservationIgnored private var pendingCR = false

    var partial: String { Self.stripANSI(partialRaw) }

    private static let maxLines = 5000

    /// 餵入一段輸出，回傳這次完成的完整行（已去除色碼）。
    @discardableResult
    func feed(_ chunk: String) -> [String] {
        var committed: [String] = []
        var current = partialRaw
        for scalar in chunk.unicodeScalars {
            if pendingCR {
                pendingCR = false
                if scalar == "\n" {
                    committed.append(commit(current)); current = ""
                    continue
                }
                current = ""   // 單獨的 \r：回到行首覆寫
            }
            switch scalar {
            case "\n":
                committed.append(commit(current)); current = ""
            case "\r":
                pendingCR = true
            default:
                current.unicodeScalars.append(scalar)
            }
        }
        partialRaw = current
        return committed
    }

    func add(_ text: String, kind: ConsoleLine.Kind) {
        append(text, kind: kind)
    }

    /// 結束時把還沒換行的部分也收進來
    func flushPartial() {
        if !partial.trimmingCharacters(in: .whitespaces).isEmpty { _ = commit(partialRaw) }
        partialRaw = ""
        pendingCR = false
    }

    func clear() {
        lines.removeAll()
        partialRaw = ""
        pendingCR = false
    }

    var plainText: String {
        (lines.map(\.text) + (partial.isEmpty ? [] : [partial])).joined(separator: "\n")
    }

    func lines(since id: Int) -> [ConsoleLine] {
        lines.filter { $0.id >= id }
    }

    private func commit(_ raw: String) -> String {
        let text = Self.stripANSI(raw)
        append(text, kind: Self.classify(text))
        return text
    }

    private func append(_ text: String, kind: ConsoleLine.Kind) {
        lines.append(ConsoleLine(id: nextID, text: text, kind: kind))
        nextID += 1
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines + 500) }
    }

    static func classify(_ text: String) -> ConsoleLine.Kind {
        if text.hasPrefix("✓") { return .ok }
        if text.hasPrefix("!") { return .warn }
        if text.hasPrefix("✗") || isShellError(text) { return .bad }
        if text.hasPrefix("▸") { return .step }
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("[dry-run]") { return .dim }
        return .plain
    }

    /// bash 本身的錯誤（例如「…/winsteam: line 308: X: unbound variable」）
    static func isShellError(_ text: String) -> Bool {
        text.contains("unbound variable") || text.range(of: #"winsteam: line \d+: "#, options: .regularExpression) != nil
    }

    private static let ansi = try! NSRegularExpression(
        pattern: "\u{1B}(?:\\[[0-9;?]*[ -/]*[@-~]|\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|[()][0-9A-Za-z]|[=>])")

    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return ansi.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }
}
