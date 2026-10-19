import Foundation
import HighlightSwift

/// Colors a block of code. Returns nil when the code should be shown plain (no or unknown language).
public protocol CodeHighlighter: Sendable {
    func highlight(_ code: String, language: String?) async -> AttributedString?
}

/// Token colors for code, as hex strings. The defaults suit the app's elevated dark surface.
public struct SyntaxPalette: Sendable, Hashable {
    public var text = "#E6E6EA"
    public var comment = "#6F7480"
    public var keyword = "#C792EA"
    public var string = "#8FD6A5"
    public var number = "#F2994A"
    public var title = "#7AA2F7"
    public var type = "#4EC9D4"
    public var attribute = "#7FDBCA"
    public var meta = "#F2C94C"
    public var deletion = "#EB5757"

    public init() {}

    var css: String {
        """
        .hljs { color: \(text); }
        .hljs-comment, .hljs-quote { color: \(comment); }
        .hljs-keyword, .hljs-selector-tag, .hljs-operator { color: \(keyword); }
        .hljs-string, .hljs-regexp, .hljs-addition, .hljs-template-tag { color: \(string); }
        .hljs-number, .hljs-literal, .hljs-symbol, .hljs-bullet { color: \(number); }
        .hljs-title, .hljs-section, .hljs-function { color: \(title); }
        .hljs-built_in, .hljs-type, .hljs-class { color: \(type); }
        .hljs-attr, .hljs-attribute, .hljs-variable, .hljs-template-variable, .hljs-property, .hljs-params { color: \(attribute); }
        .hljs-meta, .hljs-doctag, .hljs-tag { color: \(meta); }
        .hljs-deletion { color: \(deletion); }
        """
    }
}

/// highlight.js (via HighlightSwift) behind `CodeHighlighter`. Work happens on this actor, never the
/// main thread; the JavaScript context is created on first use; results are cached.
public actor HighlightSwiftHighlighter: CodeHighlighter {
    private struct Key: Hashable {
        var language: String
        var code: String
    }

    private let highlight = Highlight()
    private let colors: HighlightColors
    private var cache: [Key: AttributedString?] = [:]

    private let isAvailable: Bool

    public init(palette: SyntaxPalette = SyntaxPalette()) {
        colors = .custom(css: palette.css, background: "")
        // HighlightSwift traps if its resource bundle is missing. Inside an app bundle that means
        // Contents/Resources; if it is not there, show code plain instead of crashing.
        if Bundle.main.bundlePath.hasSuffix(".app") {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("HighlightSwift_HighlightSwift.bundle")
            isAvailable = bundled.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        } else {
            isAvailable = true
        }
    }

    public func highlight(_ code: String, language: String?) async -> AttributedString? {
        guard isAvailable,
              let language = language?.trimmingCharacters(in: .whitespaces).lowercased(), !language.isEmpty,
              !code.isEmpty
        else { return nil }
        let key = Key(language: language, code: code)
        if let cached = cache[key] { return cached }

        let result: AttributedString?
        do {
            let response = try await highlight.request(code, mode: .languageAlias(language), colors: colors)
            result = response.isUndefined ? nil : response.attributedText
        } catch {
            result = nil // unknown language or highlight.js failure: show plain
        }
        cache[key] = .some(result)
        return result
    }
}
