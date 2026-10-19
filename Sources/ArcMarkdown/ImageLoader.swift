import AppKit
import Foundation

public enum ImageLoadResult: Sendable, Equatable {
    case loaded(Data)
    case failed
}

/// Loads Markdown images: http(s) URLs over the network, `file:` URLs and absolute paths from disk.
/// Results are cached for the lifetime of the loader (the app session); failures are cached too,
/// so a dead URL is not retried on every redraw.
public actor ImageLoader {
    private let session: URLSession
    private let cache = NSCache<NSString, NSData>()
    private var failures: Set<String> = []

    public init(session: URLSession = .shared) {
        self.session = session
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    public func load(_ source: String) async -> ImageLoadResult {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = cache.object(forKey: source as NSString) { return .loaded(cached as Data) }
        if failures.contains(source) { return .failed }

        guard let data = await fetch(source), NSImage(data: data) != nil else {
            failures.insert(source)
            return .failed
        }
        cache.setObject(data as NSData, forKey: source as NSString, cost: data.count)
        return .loaded(data)
    }

    private func fetch(_ source: String) async -> Data? {
        if source.hasPrefix("/") {
            return try? Data(contentsOf: URL(fileURLWithPath: source))
        }
        guard let url = URL(string: source) else { return nil }
        switch url.scheme?.lowercased() {
        case "file":
            return try? Data(contentsOf: url)
        case "http", "https":
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return data
        default:
            return nil
        }
    }
}
