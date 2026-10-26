import Foundation
import SwiftUI
import AppKit
import Darwin

 enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case best, p1080, p720, p480
    var id: String { rawValue }
    var label: String { switch self { case .best: return "Mejor calidad"; case .p1080: return "1080p"; case .p720: return "720p"; case .p480: return "480p" } }
    var height: Int? { switch self { case .best: return nil; case .p1080: return 1080; case .p720: return 720; case .p480: return 480 } }
}
enum DownloadFormat: String, CaseIterable, Identifiable, Codable {
    case video, audio
    var id: String { rawValue }
    var label: String { self == .video ? "Video MP4" : "Audio MP3" }
}
enum DownloadStatus: String, Codable {
    case queued, downloading, completed, partial, failed, cancelled
    var label: String { switch self { case .queued: return "En cola"; case .downloading: return "Descargando"; case .completed: return "Completado"; case .partial: return "Parcial"; case .failed: return "Error"; case .cancelled: return "Cancelado" } }
}
struct DownloadItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var url: String
    var status: DownloadStatus = .queued
    var progress: Double = 0
    var speed: String = ""
    var eta: String = ""
    var filePath: String?
    var error: String?
    var thumbnail: URL?
    var quality: VideoQuality = .best
    var format: DownloadFormat = .video
    var destination: String = ""
    var options: DownloadOptions?
    var filePaths: [String]?
    var metadataPaths: [String]?
    var completedCount: Int?
    var collectionIndex: Int?
    var collectionCount: Int?
    var warning: String?
}

/// Owns one subprocess at a time. All observable state changes occur on the main actor.
@MainActor final class DownloadStore: ObservableObject {
    @Published var items: [DownloadItem] = []
    @Published var folder: URL { didSet { persist() } }
    @Published var quality: VideoQuality = .best { didSet { persist() } }
    @Published var format: DownloadFormat = .video { didSet { persist() } }
    @Published var options = DownloadOptions() { didSet { persist() } }
    @Published var isProbing = false
    @Published var isInspecting = false
    @Published var error: String?
    private var process: Process?
    private var activeID: UUID?
    private var outputBuffer = Data()
    private var diagnostic = ""
    private var cancelled = Set<UUID>()
    private let storage: URL
    private var loaded = false
    private var metadataFailure: String?
    private let fixtureInfo: URL?

    private struct Saved: Codable {
        var items: [DownloadItem]
        var folder: String
        var quality: VideoQuality
        var format: DownloadFormat
        var options: DownloadOptions?
    }
    init(storageRoot: URL? = nil, defaultFolder: URL? = nil, fixtureInfo: URL? = nil) {
        self.fixtureInfo = fixtureInfo
        let fm = Foundation.FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storage = (storageRoot ?? support.appendingPathComponent("q_YTDownloader")).appendingPathComponent("history.json")
        folder = defaultFolder ?? (fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser).appendingPathComponent("q_YTDownloader")
        if let data = try? Data(contentsOf: storage), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            items = saved.items.map { item in
                var recovered = item
                if recovered.status == .downloading || recovered.status == .queued {
                    recovered.status = .cancelled
                    recovered.error = "La descarga fue interrumpida. Puedes reintentarla."
                }
                return recovered
            }
            folder = URL(fileURLWithPath: saved.folder, isDirectory: true)
            quality = saved.quality
            format = saved.format
            options = saved.options ?? DownloadOptions()
        }
        loaded = true
    }
    func add(url: String, options selectedOptions: DownloadOptions? = nil) {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: cleaned), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme), parsed.host != nil else {
            error = "Introduce un enlace válido que empiece por https:// o http://."
            return
        }
        error = nil
        let jobOptions = selectedOptions ?? options
        items.insert(DownloadItem(title: parsed.host ?? "Video", url: cleaned, quality: quality, format: format, destination: folder.path, options: jobOptions), at: 0)
        persist()
        startNext()
    }
    func inspect(url: String, channel: Bool = false) async -> LinkPreview? {
        guard !isProbing else { return nil }
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: cleaned), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil else {
            error = "Introduce un enlace http:// o https:// válido."; return nil
        }
        guard let bin = Bundle.main.resourceURL?.appendingPathComponent("bin") else { return nil }
        isProbing = true; error = nil
        defer { isProbing = false }
        let collection = channel || parsed.path == "/playlist"
        var arguments = ["--ignore-config", "--no-colors", "--dump-single-json", "--skip-download", "--socket-timeout", "20", "--retries", "1"]
        arguments += collection ? ["--yes-playlist", "--flat-playlist", "--playlist-end", "1"] : ["--no-playlist"]
        arguments += DownloadCommand.runtimeArguments(bin: bin) + ["--", cleaned]
        do {
            let value = try await MetadataProbe.run(executable: bin.appendingPathComponent("yt-dlp"), arguments: arguments)
            let chapters = (value["chapters"] as? [[String: Any]] ?? []).compactMap { chapter -> VideoChapter? in
                guard let start = (chapter["start_time"] as? NSNumber)?.doubleValue, let end = (chapter["end_time"] as? NSNumber)?.doubleValue else { return nil }
                return VideoChapter(title: chapter["title"] as? String ?? "Capítulo", start: start, end: end)
            }
            let isCollection = ["playlist", "multi_video"].contains(value["_type"] as? String ?? "")
            if channel && !isCollection {
                self.error = "Este enlace no corresponde a una colección. Introduce la URL del canal."; return nil
            }
            return LinkPreview(url: cleaned, title: value["title"] as? String ?? parsed.host!, author: value["channel"] as? String ?? value["uploader"] as? String, publicationDate: value["release_date"] as? String ?? value["upload_date"] as? String, playlistURL: DownloadCommand.playlistURL(for: parsed) ?? (isCollection ? cleaned : nil), chapters: chapters, isCollection: isCollection, count: value["playlist_count"] as? Int)
        } catch { self.error = error.localizedDescription; return nil }
    }
    func cancel(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if activeID == id {
            cancelled.insert(id)
            items[index].status = .cancelled
            if let running = process {
                stopChildren(of: running.processIdentifier)
                running.terminate()
            }
        } else if items[index].status == .queued { items[index].status = .cancelled }
        persist()
    }
    func retry(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), [.failed, .partial, .cancelled].contains(items[index].status) else { return }
        items[index].status = .queued
        items[index].progress = 0
        items[index].error = nil
        items[index].speed = ""
        items[index].eta = ""
        items[index].warning = nil
        persist()
        startNext()
    }
    func remove(id: UUID) {
        cancel(id: id)
        items.removeAll { $0.id == id }
        persist()
    }
    func clearCompleted() {
        items.removeAll { $0.status == .completed }
        persist()
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Seleccionar carpeta"
        if panel.runModal() == .OK, let selected = panel.url { folder = selected }
    }
    func reveal(item: DownloadItem) {
        let paths = item.filePaths ?? item.filePath.map { [$0] } ?? []
        if !paths.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) }) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: item.destination, isDirectory: true)) }
    }
    /// Stop only descendants of this download, including an active ffmpeg conversion.
    private func stopChildren(of parent: pid_t) {
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/bin/ps")
        listing.arguments = ["-axo", "pid=,ppid="]
        let pipe = Pipe()
        listing.standardOutput = pipe
        listing.standardError = FileHandle.nullDevice
        guard (try? listing.run()) != nil else { return }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let pairs = output.split(separator: "\n").compactMap { line -> (pid_t, pid_t)? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { return nil }
            return (pid, ppid)
        }
        func stop(_ pid: pid_t) {
            for (child, ppid) in pairs where ppid == pid && child != pid {
                stop(child)
                Darwin.kill(child, SIGTERM)
            }
        }
        stop(parent)
    }
    private func startNext() {
        guard activeID == nil, let item = items.last(where: { $0.status == .queued }) else { return }
        let bin = Bundle.main.resourceURL?.appendingPathComponent("bin")
        guard let executable = bin?.appendingPathComponent("yt-dlp"), Foundation.FileManager.default.isExecutableFile(atPath: executable.path) else {
            update(item.id) { $0.status = .failed; $0.error = "No se encontró el motor yt-dlp incluido en la aplicación." }
            startNext()
            return
        }
        do { try Foundation.FileManager.default.createDirectory(at: URL(fileURLWithPath: item.destination, isDirectory: true), withIntermediateDirectories: true) }
        catch { update(item.id) { $0.status = .failed; $0.error = error.localizedDescription }; startNext(); return }
        let p = Process()
        p.executableURL = executable
        var args = DownloadCommand.arguments(for: item, bin: bin!)
        if let fixtureInfo {
            args.removeLast(2)
            args += ["--no-clean-info-json", "--load-info-json", fixtureInfo.path]
        }
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        activeID = item.id
        process = p
        outputBuffer = Data()
        diagnostic = ""
        metadataFailure = nil
        isInspecting = true
        update(item.id) { $0.status = .downloading }
        do {
            try p.run()
            // One reader owns the pipe. FIFO dispatch onto the main queue guarantees
            // the last metadata line is consumed before completion is evaluated.
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    DispatchQueue.main.async { [weak self] in self?.consume(data, id: item.id) }
                }
                p.waitUntilExit()
                let code = p.terminationStatus
                DispatchQueue.main.async { [weak self] in self?.finish(id: item.id, code: code) }
            }
        } catch {
            diagnostic = error.localizedDescription
            finish(id: item.id, code: -1)
        }
    }
    private func consume(_ data: Data, id: UUID) {
        guard activeID == id else { return }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = String(decoding: outputBuffer[..<newline], as: UTF8.self)
            outputBuffer.removeSubrange(...newline)
            parse(line, id: id)
        }
        if outputBuffer.count > 2_000_000 {
            metadataFailure = "Los metadatos exceden el tamaño admitido."
            outputBuffer.removeAll()
        }
    }
    private func parse(_ raw: String, id: UUID) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("Q_PROGRESS\t") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { return }
            update(id, save: false) { item in
                if let percent = Double(parts[1].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) { item.progress = min(1, max(0, percent / 100)) }
                item.speed = parts[2].trimmingCharacters(in: .whitespaces)
                item.eta = parts[3].trimmingCharacters(in: .whitespaces)
            }
            isInspecting = false
        } else if line.hasPrefix("Q_TITLE\t") {
            if let value = try? JSONSerialization.jsonObject(with: Data(line.dropFirst("Q_TITLE\t".count).utf8)) as? [String: Any] {
                update(id) {
                    $0.title = value["title"] as? String ?? $0.title
                    $0.collectionIndex = value["playlist_index"] as? Int
                    $0.collectionCount = value["playlist_count"] as? Int
                    $0.progress = 0
                }
            }
            isInspecting = false
        } else if line.hasPrefix("Q_WARNING\t") {
            if let warning = try? JSONSerialization.jsonObject(with: Data(line.dropFirst("Q_WARNING\t".count).utf8), options: [.fragmentsAllowed]) as? String {
                update(id) { $0.warning = warning }
            }
        } else if line.hasPrefix("Q_META\t") {
            do {
                guard let value = try JSONSerialization.jsonObject(with: Data(line.dropFirst("Q_META\t".count).utf8)) as? [String: Any],
                      let path = value["filepath"] as? String else { throw CocoaError(.fileReadCorruptFile) }
                var paths = [path]
                let chapters = value["chapters"] as? [[String: Any]] ?? []
                let chapterPaths = chapters.compactMap { $0["filepath"] as? String }.filter { Foundation.FileManager.default.fileExists(atPath: $0) }
                paths += chapterPaths
                update(id) { item in
                    item.filePath = path
                    var all = item.filePaths ?? []
                    let alreadySaved = all.contains(path)
                    for path in paths where !all.contains(path) { all.append(path) }
                    item.filePaths = all
                    if !alreadySaved { item.completedCount = (item.completedCount ?? 0) + 1 }
                    if item.options?.splitChapters == true, chapterPaths.isEmpty { item.warning = "Este video no tiene capítulos disponibles para dividir." }
                    if let warning = value["q_chapter_warning"] as? String { item.warning = warning }
                }
                if items.first(where: { $0.id == id })?.options?.metadata == true {
                    let textPath = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("txt")
                    try MetadataText.render(value).write(to: textPath, atomically: true, encoding: .utf8)
                    update(id) { item in
                        var all = item.metadataPaths ?? []
                        if !all.contains(textPath.path) { all.append(textPath.path) }
                        item.metadataPaths = all
                    }
                }
            } catch { metadataFailure = "No se pudieron guardar los metadatos: \(error.localizedDescription)" }
        } else {
            diagnostic += line + "\n"
            if diagnostic.count > 12000 { diagnostic = String(diagnostic.suffix(12000)) }
        }
    }
    private func finish(id: UUID, code: Int32) {
        guard activeID == id else { return }
        if !outputBuffer.isEmpty { parse(String(decoding: outputBuffer, as: UTF8.self), id: id) }
        let wasCancelled = cancelled.remove(id) != nil
        update(id) { item in
            item.speed = ""; item.eta = ""
            if wasCancelled { item.status = .cancelled }
            else if code == 0, metadataFailure == nil, let path = item.filePath, Foundation.FileManager.default.fileExists(atPath: path) { item.status = .completed; item.progress = 1 }
            else {
                item.status = (item.filePaths?.isEmpty == false) ? .partial : .failed
                let lines = diagnostic.components(separatedBy: .newlines).filter { $0.contains("ERROR:") }
                item.error = metadataFailure ?? lines.last ?? (diagnostic.isEmpty ? "No se pudo completar la descarga." : String(diagnostic.suffix(1800)))
            }
        }
        process = nil; activeID = nil; isInspecting = false; outputBuffer = Data()
        startNext()
    }
    private func update(_ id: UUID, save: Bool = true, _ body: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
        if save { persist() }
    }
    private func persist() {
        guard loaded else { return }
        do {
            try Foundation.FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Saved(items: items, folder: folder.path, quality: quality, format: format, options: options))
            try data.write(to: storage, options: .atomic)
        } catch { NSLog("Download history could not be saved: %@", error.localizedDescription) }
    }
}
