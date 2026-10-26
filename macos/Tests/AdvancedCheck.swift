import Foundation
import Darwin

@main struct AdvancedCheck {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let base = CommandLine.arguments[1]
        func fail(_ message: String) -> Never { print("FAIL: " + message); exit(1) }
        func fixture(_ id: String, _ title: String) -> [String: Any] {
            ["_type": "video", "id": id, "title": title, "description": "Descripción de prueba\nSegunda línea: ñ, á, naranja.", "upload_date": "20261001", "release_date": "20261002", "uploader": "q pruebas", "channel": "Canal de prueba", "channel_id": "channel-test", "webpage_url": base, "extractor": "generic", "extractor_key": "Generic", "duration": 2, "tags": ["prueba", "metadatos"], "chapters": [["title": "Inicio", "start_time": 0.0, "end_time": 1.0], ["title": "Final", "start_time": 1.0, "end_time": 2.0]], "formats": [["url": base, "ext": "mp4", "format_id": "http", "height": 180, "width": 320, "vcodec": "h264", "acodec": "aac"]]]
        }
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let infoURL = root.appendingPathComponent("fixture.json")
        try! JSONSerialization.data(withJSONObject: fixture("chapter-test", "Video por capítulos")).write(to: infoURL)
        let store = DownloadStore(storageRoot: root.appendingPathComponent("history"), defaultFolder: root.appendingPathComponent("downloads"), fixtureInfo: infoURL)
        store.options = DownloadOptions(metadata: true, publicationDate: true, splitChapters: true)
        store.add(url: base)
        let id = store.items.first!.id
        await wait(store, id)
        guard let item = store.items.first, item.status == .completed, let path = item.filePath else { fail(store.items.first?.error ?? "Chapter download timed out") }
        guard URL(fileURLWithPath: path).lastPathComponent.hasPrefix("2026-10-02") else { fail("Publication date missing: " + path) }
        guard let metadataPath = item.metadataPaths?.first, let text = try? String(contentsOfFile: metadataPath, encoding: .utf8), text.contains("Descripción de prueba"), text.contains("Segunda línea"), text.contains("channel-test"), text.contains("Inicio"), text.contains("Final") else { fail("TXT metadata missing or incomplete") }
        guard let files = item.filePaths, files.count == 3 else { fail("Expected full video and 2 chapters: \(item.filePaths ?? []) warning=\(item.warning ?? "")") }
        for path in files {
            guard ((try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? 0) > 500 else { fail("Empty chapter " + path) }
        }
        print("PASS publication-date filename, UTF-8 TXT description/metadata, two real chapter files")
        let playlistURL = root.appendingPathComponent("playlist.json")
        let playlist: [String: Any] = ["_type": "playlist", "id": "playlist-test", "title": "Lista de prueba", "extractor": "generic", "extractor_key": "Generic", "entries": [fixture("video-1", "Primer video"), fixture("video-2", "Segundo video")]]
        try! JSONSerialization.data(withJSONObject: playlist).write(to: playlistURL)
        let collectionStore = DownloadStore(storageRoot: root.appendingPathComponent("collection-history"), defaultFolder: root.appendingPathComponent("collections"), fixtureInfo: playlistURL)
        collectionStore.options = DownloadOptions(metadata: true, publicationDate: true, splitChapters: false, scope: .playlist)
        collectionStore.add(url: base)
        let collectionID = collectionStore.items.first!.id
        await wait(collectionStore, collectionID)
        guard let collection = collectionStore.items.first, collection.status == .completed, collection.completedCount == 2, collection.metadataPaths?.count == 2 else { fail("Playlist: \(collectionStore.items.first?.error ?? "") count=\(collectionStore.items.first?.completedCount ?? -1)") }
        guard collection.filePaths?.allSatisfy({ $0.contains("Lista de prueba/") }) == true else { fail("Playlist folder not preserved") }
        print("PASS complete playlist, separate metadata per video and collection folder")
        collectionStore.options.scope = .channel
        collectionStore.add(url: base)
        let channelID = collectionStore.items.first!.id
        await wait(collectionStore, channelID)
        guard collectionStore.items.first?.status == .completed, collectionStore.items.first?.completedCount == 2 else { fail("Channel collection download failed") }
        print("PASS channel collection downloads all available entries")
        let candidate = DownloadCommand.playlistURL(for: URL(string: "https://www.youtube.com/watch?v=test&list=PL-test")!)
        guard candidate == "https://www.youtube.com/playlist?list=PL-test", DownloadCommand.playlistURL(for: URL(string: "https://example.com/watch?list=PL-test")!) == nil else { fail("Playlist URL detection") }
        let noDateURL = root.appendingPathComponent("no-date.json")
        var noDate = fixture("no-date", "Sin fecha")
        noDate.removeValue(forKey: "upload_date"); noDate.removeValue(forKey: "release_date"); noDate.removeValue(forKey: "chapters")
        try! JSONSerialization.data(withJSONObject: noDate).write(to: noDateURL)
        let unknown = DownloadStore(storageRoot: root.appendingPathComponent("unknown-history"), defaultFolder: root.appendingPathComponent("unknown"), fixtureInfo: noDateURL)
        unknown.options = DownloadOptions(metadata: true, publicationDate: true, splitChapters: true)
        unknown.add(url: base)
        await wait(unknown, unknown.items.first!.id)
        guard unknown.items.first?.status == .completed, unknown.items.first?.filePath?.contains("sin-fecha") == true, unknown.items.first?.warning != nil else { fail("Unavailable dates/chapters weren't reported") }
        print("PASS unavailable date and chapters reported without inventing values")
        let restored = DownloadStore(storageRoot: root.appendingPathComponent("history"))
        guard restored.options == store.options, restored.items.first?.filePaths?.count == 3 else { fail("Advanced options or chapter history not persisted") }
        print("PASS advanced preferences and output paths persisted")
        guard let preview = await store.inspect(url: base), preview.title.contains("sample"), !store.isProbing else { fail("Live metadata inspection failed") }
        guard await store.inspect(url: base, channel: true) == nil, store.error != nil else { fail("Single video was admitted as a whole channel") }
        print("PASS live link inspection and invalid channel rejection")
        var broken = fixture("missing", "No disponible")
        var formats = broken["formats"] as! [[String: Any]]
        formats[0]["url"] = base.replacingOccurrences(of: "sample.mp4", with: "missing-test-file.mp4")
        broken["formats"] = formats
        let partialURL = root.appendingPathComponent("partial.json")
        try! JSONSerialization.data(withJSONObject: ["_type": "playlist", "id": "partial", "title": "Lista parcial", "extractor": "generic", "extractor_key": "Generic", "entries": [fixture("exists", "Disponible"), broken]]).write(to: partialURL)
        let partial = DownloadStore(storageRoot: root.appendingPathComponent("partial-history"), defaultFolder: root.appendingPathComponent("partial"), fixtureInfo: partialURL)
        partial.options.scope = .playlist
        partial.add(url: base)
        let partialID = partial.items.first!.id
        await wait(partial, partialID)
        guard partial.items.first?.status == .partial, partial.items.first?.completedCount == 1, partial.items.first?.error != nil else { fail("Incomplete collection not reported as partial") }
        partial.retry(id: partialID)
        await wait(partial, partialID)
        guard partial.items.first?.status == .partial, partial.items.first?.completedCount == 1 else { fail("Retry duplicated completed counts") }
        print("PASS partial collection and retry without duplicate counts")
        print("ADVANCED CHECK PASSED")
        exit(0)
    }
    @MainActor static func wait(_ store: DownloadStore, _ id: UUID) async {
        for _ in 0..<1800 {
            if let item = store.items.first(where: { $0.id == id }), ![.queued, .downloading].contains(item.status) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
