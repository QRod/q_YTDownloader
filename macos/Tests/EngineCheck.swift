import Foundation
import Darwin

@main struct EngineCheck {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 3, let base = URL(string: CommandLine.arguments[1]) else {
            print("Usage: EngineCheck <http://127.0.0.1:PORT/sample.mp4> <temporary output directory>")
            exit(2)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let store = DownloadStore(storageRoot: root.appendingPathComponent("history"), defaultFolder: root.appendingPathComponent("downloads"))
        func fail(_ text: String) -> Never { print("FAIL: " + text); exit(1) }
        store.add(url: "file:///etc/passwd")
        guard store.items.isEmpty, store.error != nil else { fail("Invalid scheme was accepted") }
        print("PASS invalid scheme rejected")
        store.add(url: base.absoluteString)
        guard let videoID = store.items.first?.id else { fail("Video was not queued") }
        guard await wait(store, id: videoID), let video = store.items.first(where: { $0.id == videoID }), video.status == .completed, let videoPath = video.filePath else {
            fail("Video download: \(store.items.first?.error ?? "timed out")")
        }
        guard (try? Data(contentsOf: URL(fileURLWithPath: videoPath)).count) ?? 0 > 1024 else { fail("Video file missing or empty") }
        print("PASS video downloaded: " + videoPath)
        store.format = .audio
        store.add(url: base.absoluteString)
        let audioID = store.items.first!.id
        guard await wait(store, id: audioID), let audio = store.items.first(where: { $0.id == audioID }), audio.status == .completed, let audioPath = audio.filePath, audioPath.hasSuffix(".mp3") else {
            fail("Audio conversion: \(store.items.first?.error ?? "timed out")")
        }
        guard (try? Data(contentsOf: URL(fileURLWithPath: audioPath)).count) ?? 0 > 512 else { fail("Audio file empty") }
        print("PASS MP3 conversion: " + audioPath)
        store.add(url: base.deletingLastPathComponent().appendingPathComponent("missing-test-file.mp4").absoluteString)
        let missingID = store.items.first!.id
        store.format = .video
        store.add(url: base.absoluteString)
        let cancelledID = store.items.first!.id
        store.cancel(id: cancelledID)
        guard store.items.first?.status == .cancelled else { fail("Queued cancellation failed") }
        print("PASS queued download cancelled")
        guard await wait(store, id: missingID), let missing = store.items.first(where: { $0.id == missingID }), missing.status == .failed, missing.error != nil else { fail("Missing URL did not produce a failure") }
        print("PASS missing URL recorded as failed")
        store.retry(id: missingID)
        guard await wait(store, id: missingID), store.items.first(where: { $0.id == missingID })?.status == .failed else { fail("Failed download retry did not finish") }
        print("PASS retry processed")
        store.retry(id: cancelledID)
        guard await wait(store, id: cancelledID), store.items.first(where: { $0.id == cancelledID })?.status == .completed else { fail("Cancelled job retry failed") }
        print("PASS cancelled download retried successfully")
        let restored = DownloadStore(storageRoot: root.appendingPathComponent("history"))
        guard restored.items.count == store.items.count, restored.items.filter({ $0.status == .completed }).count == 3 else { fail("History did not persist") }
        print("PASS isolated history persisted")
        print("ENGINE CHECK PASSED")
        exit(0)
    }
    @MainActor static func wait(_ store: DownloadStore, id: UUID) async -> Bool {
        for _ in 0..<1200 {
            guard let item = store.items.first(where: { $0.id == id }) else { return false }
            if [.completed, .failed, .cancelled].contains(item.status) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}
