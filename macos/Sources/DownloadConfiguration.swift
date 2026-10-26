import Foundation

enum DownloadScope: String, Codable, CaseIterable, Identifiable {
    case video, playlist, channel
    var id: String { rawValue }
    var label: String { switch self { case .video: return "Video"; case .playlist: return "Lista completa"; case .channel: return "Canal completo" } }
}
struct DownloadOptions: Codable, Equatable {
    var metadata = false
    var publicationDate = false
    var splitChapters = false
    var scope: DownloadScope = .video
}
struct VideoChapter: Codable, Identifiable {
    let title: String
    let start: Double
    let end: Double
    var id: Double { start }
    var time: String { String(format: "%02d:%02d", Int(start) / 60, Int(start) % 60) }
}
struct LinkPreview {
    let url: String
    let title: String
    let author: String?
    let publicationDate: String?
    let playlistURL: String?
    let chapters: [VideoChapter]
    let isCollection: Bool
    let count: Int?
    var defaultScope: DownloadScope { isCollection ? .playlist : .video }
}
enum DownloadCommand {
    static let metadataTemplate = "%(.{id,title,description,webpage_url,original_url,upload_date,release_date,uploader,uploader_id,channel,channel_id,channel_url,duration,view_count,like_count,tags,categories,chapters,filepath,playlist,playlist_index,playlist_count,q_chapter_warning})j"
    static func runtimeArguments(bin: URL) -> [String] {
        let bundled = bin.appendingPathComponent("node")
        let configured = try? String(contentsOf: bin.appendingPathComponent("node-path.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let node = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : configured.map { URL(fileURLWithPath: $0) } ?? bundled
        return FileManager.default.isExecutableFile(atPath: node.path) ? ["--js-runtimes", "node:" + node.path] : []
    }
    static func arguments(for item: DownloadItem, bin: URL) -> [String] {
        let options = item.options ?? DownloadOptions()
        var args = ["--ignore-config", "--newline", "--no-colors", "--progress", "--progress-template", "download:Q_PROGRESS\t%(progress._percent_str)s\t%(progress._speed_str)s\t%(progress._eta_str)s", "--print", "before_dl:Q_TITLE\t%(.{title,playlist_index,playlist_count})j", "--print", "after_move:Q_META\t" + metadataTemplate, "--no-simulate", "--ffmpeg-location", bin.path, "--paths", item.destination]
        if options.scope == .video { args += ["--no-playlist"] }
        else { args += ["--yes-playlist", "--lazy-playlist"] }
        let date = options.publicationDate ? "%(release_date>%Y-%m-%d,upload_date>%Y-%m-%d|sin-fecha)s_" : ""
        let collection = options.scope == .video ? "" : "%(playlist_title,channel,uploader|Colección).100B/"
        let channel = "%(channel,uploader|Canal).60B"
        let title = "%(title).160B"
        let name = date + (item.format == .video ? channel + "_" : "") + title
        args += ["--output", collection + name + ".%(ext)s"]
        if options.splitChapters {
            let chapterName = item.format == .video ? date + channel + "_%(title).110B_%(section_title).65B" : date + "%(section_number)02d_%(section_title).160B"
            args += ["--split-chapters", "--output", "chapter:" + collection + name + "/" + chapterName + ".%(ext)s"]
        }
        if item.format == .audio {
            args += ["-f", "bestaudio/best", "--extract-audio", "--audio-format", "mp3", "--parse-metadata", "%(channel,uploader|Canal)s:%(meta_artist)s", "--embed-metadata"]
            if options.splitChapters {
                args += ["--parse-metadata", "%(title)s:%(meta_album)s", "--write-thumbnail", "--convert-thumbnails", "jpg",
                         "--no-plugin-dirs", "--plugin-dirs", bin.deletingLastPathComponent().appendingPathComponent("Plugins").path,
                         "--use-postprocessor", "QChapterMetadata:when=after_move"]
            }
        }
        else {
            let limit = item.quality.height.map { "[height<=\($0)]" } ?? ""
            args += ["-f", "bv*\(limit)+ba/b\(limit)", "--merge-output-format", "mp4", "--remux-video", "mp4"]
        }
        args += runtimeArguments(bin: bin)
        args += ["--", item.url]
        return args
    }
    static func playlistURL(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be",
              let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "list" })?.value,
              !list.isEmpty else { return nil }
        var result = URLComponents(string: "https://www.youtube.com/playlist")!
        result.queryItems = [URLQueryItem(name: "list", value: list)]
        return result.url?.absoluteString
    }
    static func isChannel(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasPrefix("/@") || path.hasPrefix("/channel/") || path.hasPrefix("/c/") || path.hasPrefix("/user/")
    }
}

enum MetadataText {
    static func render(_ value: [String: Any]) -> String {
        func text(_ key: String) -> String {
            guard let item = value[key], !(item is NSNull) else { return "No disponible" }
            if let items = item as? [String] { return items.joined(separator: ", ") }
            return String(describing: item)
        }
        let fields = [("Título", "title"), ("ID", "id"), ("Enlace", "webpage_url"), ("Autor", "uploader"), ("Canal", "channel"), ("ID de canal", "channel_id"), ("Canal URL", "channel_url"), ("Fecha de publicación", "release_date"), ("Fecha de subida", "upload_date"), ("Duración (s)", "duration"), ("Visualizaciones", "view_count"), ("Me gusta", "like_count"), ("Etiquetas", "tags"), ("Categorías", "categories"), ("Lista", "playlist"), ("Posición en lista", "playlist_index")]
        var lines = fields.map { "\($0.0): \(text($0.1))" }
        lines += ["", "Descripción", "───────────", text("description"), "", "Capítulos", "─────────"]
        if let chapters = value["chapters"] as? [[String: Any]], !chapters.isEmpty {
            for chapter in chapters {
                let start = (chapter["start_time"] as? NSNumber)?.doubleValue ?? 0
                let end = (chapter["end_time"] as? NSNumber)?.doubleValue ?? start
                lines.append(String(format: "%02d:%02d – %02d:%02d · %@", Int(start) / 60, Int(start) % 60, Int(end) / 60, Int(end) % 60, chapter["title"] as? String ?? "Capítulo"))
            }
        } else { lines.append("No disponibles") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Bounded metadata query. Runs outside the main actor and drains both streams.
enum MetadataProbe {
    static func run(executable: URL, arguments: [String]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe(), stderr = Pipe()
                process.executableURL = executable; process.arguments = arguments
                process.standardOutput = stdout; process.standardError = stderr; process.standardInput = FileHandle.nullDevice
                let errorQueue = DispatchQueue(label: "q.metadata.stderr")
                var diagnostic = Data()
                let group = DispatchGroup()
                do {
                    try process.run()
                    group.enter()
                    errorQueue.async {
                        while true {
                            let data = stderr.fileHandleForReading.availableData
                            if data.isEmpty { break }
                            diagnostic.append(data)
                            if diagnostic.count > 12000 { diagnostic.removeFirst(diagnostic.count - 12000) }
                        }
                        group.leave()
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 90) { if process.isRunning { process.terminate() } }
                    var data = Data()
                    while true {
                        let chunk = stdout.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        data.append(chunk)
                        if data.count > 8_000_000 { process.terminate(); break }
                    }
                    process.waitUntilExit(); group.wait()
                    guard process.terminationStatus == 0 else {
                        let error = String(decoding: diagnostic, as: UTF8.self)
                        throw NSError(domain: "q_YTDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: error.isEmpty ? "No se pudo analizar el enlace." : String(error.suffix(2000))])
                    }
                    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
                    continuation.resume(returning: value)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
