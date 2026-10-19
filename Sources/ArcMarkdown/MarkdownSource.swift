import Foundation

public enum MarkdownSource {
    /// Flips the `[ ]`/`[x]` at `task.range` and leaves every other byte of `source` unchanged.
    ///
    /// Returns nil when the text at the range is no longer a checkbox in the state the task was
    /// parsed with (the source changed since rendering); the caller should re-render.
    public static func toggleTask(_ task: MarkdownTask, in source: String) -> String? {
        guard let range = task.range else { return nil }
        var bytes = Array(source.utf8)
        guard range.lowerBound >= 0, range.upperBound <= bytes.count, range.count == 3,
              bytes[range.lowerBound] == UInt8(ascii: "["),
              bytes[range.upperBound - 1] == UInt8(ascii: "]")
        else { return nil }

        let mark = bytes[range.lowerBound + 1]
        let isChecked = mark == UInt8(ascii: "x") || mark == UInt8(ascii: "X")
        let isUnchecked = mark == UInt8(ascii: " ")
        guard isChecked == task.isChecked, isChecked || isUnchecked else { return nil }

        bytes[range.lowerBound + 1] = isChecked ? UInt8(ascii: " ") : UInt8(ascii: "x")
        return String(decoding: bytes, as: UTF8.self)
    }
}
