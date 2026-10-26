import Foundation
import Darwin

@main struct NamingCheck {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 4 else { exit(2) }
        let base = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let coverURL = URL(string: base)!.deletingLastPathComponent().appendingPathComponent("thumbnail.jpg").absoluteString
        let expectedCover = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let fixture: [String: Any] = ["_type": "video", "id": "naming-test", "title": "Video de prueba", "channel": "Canal de prueba", "uploader": "Autor diferente", "description": "Descripción de prueba", "upload_date": "20261001", "extractor": "generic", "extractor_key": "Generic", "webpage_url": base, "thumbnail": coverURL, "thumbnails": [["url": coverURL, "id": "0", "ext": "jpg"]], "duration": 2, "chapters": [["title": "Introducción", "start_time": 0.0, "end_time": 1.0], ["title": "Final", "start_time": 1.0, "end_time": 2.0]], "formats": [["url": base, "format_id": "http", "ext": "mp4", "height": 180, "vcodec": "h264", "acodec": "aac"]]]
        let info = root.appendingPathComponent("fixture.json")
        try! JSONSerialization.data(withJSONObject: fixture).write(to: info)
        func fail(_ message: String) -> Never { print("FAIL: " + message); exit(1) }
        let bin = Bundle.main.resourceURL!.appendingPathComponent("bin")
        func tags(_ path: String) -> String {
            let process = Process(), output = Pipe()
            process.executableURL = bin.appendingPathComponent("ffmpeg")
            process.arguments = ["-hide_banner", "-loglevel", "error", "-i", path, "-f", "ffmetadata", "-"]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try! process.run()
            let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return result
        }
        func cover(_ path: String) -> Data {
            let process = Process(), output = Pipe()
            process.executableURL = bin.appendingPathComponent("ffmpeg")
            process.arguments = ["-hide_banner", "-loglevel", "error", "-i", path, "-map", "0:v:0", "-c:v", "copy", "-frames:v", "1", "-f", "image2pipe", "-"]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try! process.run()
            let result = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return result
        }
        for (format, split, key) in [(DownloadFormat.video, false, "video"), (.video, true, "video-chapters"), (.audio, false, "audio"), (.audio, true, "audio-chapters"), (.audio, true, "audio-no-cover")] {
            let directory = root.appendingPathComponent(key)
            var selectedInfo = info
            if key == "audio-no-cover" {
                var noCover = fixture
                noCover.removeValue(forKey: "thumbnail"); noCover.removeValue(forKey: "thumbnails")
                selectedInfo = root.appendingPathComponent("no-cover.json")
                try! JSONSerialization.data(withJSONObject: noCover).write(to: selectedInfo)
            }
            let store = DownloadStore(storageRoot: directory.appendingPathComponent("history"), defaultFolder: directory.appendingPathComponent("downloads"), fixtureInfo: selectedInfo)
            store.format = format; store.options.splitChapters = split
            store.add(url: base)
            let id = store.items.first!.id
            for _ in 0..<1800 {
                if let item = store.items.first, ![.queued, .downloading].contains(item.status) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let item = store.items.first, item.id == id, item.status == .completed, let path = item.filePath else { fail("\(key): \(store.items.first?.error ?? "timeout")") }
            let expected = format == .video ? "Canal de prueba_Video de prueba.mp4" : "Video de prueba.mp3"
            guard URL(fileURLWithPath: path).lastPathComponent == expected else { fail("\(key) filename: " + path) }
            if format == .audio {
                guard tags(path).contains("artist=Canal de prueba") else { fail("Full MP3 artist is not the channel") }
            }
            if split {
                guard let files = item.filePaths, files.count == 3 else { fail("Missing chapter files") }
                for (index, title) in ["Introducción", "Final"].enumerated() {
                    let filename = format == .video ? "Canal de prueba_Video de prueba_\(title).mp4" : String(format: "%02d_%@.mp3", index + 1, title)
                    guard let chapter = files.first(where: { URL(fileURLWithPath: $0).lastPathComponent == filename }) else { fail("Missing " + filename) }
                    if format == .audio {
                        let metadata = tags(chapter)
                        guard metadata.contains("artist=Canal de prueba"), metadata.contains("album=Video de prueba") else { fail("Chapter artist/album incorrect: " + metadata) }
                        guard metadata.contains("track=\(index + 1)\n"), metadata.contains("title=\(title)\n") else { fail("Chapter track/title incorrect: " + metadata) }
                        if key == "audio-no-cover" {
                            guard item.warning?.contains("miniatura") == true, cover(chapter).isEmpty else { fail("Missing cover wasn't reported") }
                        } else {
                            guard cover(chapter) == expectedCover else { fail("Embedded cover differs from video thumbnail") }
                        }
                    }
                }
            }
            let checked = format != .audio ? "" : !split ? ", artist" : key == "audio-no-cover" ? ", artist/album/track/title and missing-cover warning" : ", artist/album/track/title and artwork"
            print("PASS \(key): filenames" + checked)
        }
        print("NAMING CHECK PASSED")
        exit(0)
    }
}
