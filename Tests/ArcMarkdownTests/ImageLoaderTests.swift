import AppKit
import Foundation
import Testing
@testable import ArcMarkdown

@Suite struct ImageLoaderTests {
    private func makePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemIndigo.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arc-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.png")
        try makePNG().write(to: url)
        return url
    }

    @Test func loadsFileURLAndAbsolutePath() async throws {
        let url = try fixture()
        let loader = ImageLoader()
        for source in [url.absoluteString, url.path] {
            guard case .loaded(let data) = await loader.load(source) else {
                Issue.record("failed to load \(source)")
                continue
            }
            #expect(NSImage(data: data) != nil)
        }
    }

    @Test func missingFileFails() async {
        let loader = ImageLoader()
        #expect(await loader.load("/definitely/not/here.png") == .failed)
        #expect(await loader.load("file:///definitely/not/here.png") == .failed)
    }

    @Test func nonImageDataFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arc-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("not-an-image.png")
        try Data("hello".utf8).write(to: file)
        #expect(await ImageLoader().load(file.path) == .failed)
    }

    @Test func unsupportedSourcesFail() async {
        let loader = ImageLoader()
        #expect(await loader.load("relative/path.png") == .failed)
        #expect(await loader.load("ftp://example.com/x.png") == .failed)
        #expect(await loader.load("") == .failed)
    }

    @Test func unreachableRemoteURLProducesFailureState() async {
        // Port 9 (discard) on localhost refuses connections immediately: no network needed.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let loader = ImageLoader(session: URLSession(configuration: configuration))
        #expect(await loader.load("http://127.0.0.1:9/d.png") == .failed)
    }

    @Test func successfulLoadsAreServedFromCacheAfterTheFileIsGone() async throws {
        let url = try fixture()
        let loader = ImageLoader()
        guard case .loaded(let first) = await loader.load(url.path) else { Issue.record("first load failed"); return }
        try FileManager.default.removeItem(at: url)
        #expect(await loader.load(url.path) == .loaded(first))
    }
}
