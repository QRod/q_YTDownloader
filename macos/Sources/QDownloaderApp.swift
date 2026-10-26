import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .dark ? "Oscuro" : "Claro" }
    var scheme: ColorScheme { self == .dark ? .dark : .light }
}
struct Palette {
    let dark: Bool
    var accent: Color { dark ? Color(red: 0.94, green: 0.53, blue: 0.26) : Color(red: 0.25, green: 0.27, blue: 0.29) }
    var background: Color { dark ? Color(red: 0.10, green: 0.11, blue: 0.12) : Color(red: 0.97, green: 0.98, blue: 0.96) }
    var surface: Color { dark ? Color(red: 0.14, green: 0.15, blue: 0.16) : .white }
    var foreground: Color { dark ? Color(red: 0.91, green: 0.91, blue: 0.90) : Color(red: 0.18, green: 0.19, blue: 0.20) }
    var border: Color { foreground.opacity(dark ? 0.09 : 0.06) }
}

#if !PREVIEW_BUILD
@main struct QDownloaderApp: App {
    @StateObject private var store = DownloadStore()
    var body: some Scene {
        WindowGroup("q_YTDownloader") {
            ContentView(store: store).frame(minWidth: 820, minHeight: 580)
        }.defaultSize(width: 1010, height: 690)
        .commands { CommandGroup(replacing: .newItem) { EmptyView() } }
    }
}
#endif

struct ContentView: View {
    @ObservedObject var store: DownloadStore
    var previewTheme: AppTheme? = nil
    @AppStorage("q_YTDownloader.theme") private var themeName = AppTheme.light.rawValue
    @State private var search = ""
    @State private var filter = "Todas"
    @State private var showInput = false
    @State private var link = ""
    @State private var preview: LinkPreview?
    @State private var scope: DownloadScope = .video
    @State private var probeError: String?
    @State private var channelMode = false
    private var theme: AppTheme { previewTheme ?? AppTheme(rawValue: themeName) ?? .light }
    private var palette: Palette { Palette(dark: theme == .dark) }
    private let filters = ["Todas", "En curso", "Completadas"]
    private var visible: [DownloadItem] {
        store.items.filter { item in
            let matches = filter == "Todas" || (filter == "En curso" && [.queued, .downloading].contains(item.status)) || (filter == "Completadas" && item.status == .completed)
            return matches && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.url.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.border)
            toolbar
            HStack(spacing: 18) {
                ForEach(filters, id: \.self) { name in
                    Button { filter = name } label: {
                        VStack(spacing: 9) {
                            Text(name).font(.system(size: 12, weight: filter == name ? .semibold : .regular)).foregroundStyle(filter == name ? palette.foreground : .secondary)
                            Rectangle().fill(filter == name ? palette.accent : .clear).frame(height: 2)
                        }
                    }.buttonStyle(.plain)
                }
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Buscar", text: $search).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 150)
                Menu {
                    Button("Quitar completadas") { store.clearCompleted() }
                    Button("Abrir carpeta") { NSWorkspace.shared.open(store.folder) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
            }.padding(.horizontal, 28).padding(.top, 18)
            if visible.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(palette.accent.opacity(0.6))
                    Text(store.items.isEmpty ? "Sin descargas" : "Sin resultados").font(.system(size: 14)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { LazyVStack(spacing: 8) { ForEach(visible) { item in DownloadRow(item: item, store: store, palette: palette) } }.padding(24) }
            }
            HStack {
                Text("\(store.items.count) descargas").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { store.chooseFolder() } label: { Label(store.folder.lastPathComponent, systemImage: "folder").font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).help(store.folder.path)
            }.padding(.horizontal, 28).padding(.vertical, 14)
        }.background(palette.background).foregroundStyle(palette.foreground)
        .tint(palette.accent).preferredColorScheme(theme.scheme)
    }
    private var header: some View {
        HStack {
            Text("q_YTDownloader").font(.system(size: 16, weight: .semibold, design: .monospaced))
            Spacer()
            Button { themeName = theme == .dark ? AppTheme.light.rawValue : AppTheme.dark.rawValue } label: {
                Image(systemName: theme == .dark ? "sun.max" : "moon").font(.system(size: 13)).frame(width: 25, height: 25)
            }.buttonStyle(.plain).help(theme == .dark ? "Cambiar a tema claro" : "Cambiar a tema oscuro")
        }.padding(.horizontal, 28).padding(.vertical, 21).background(palette.surface)
    }
    private var toolbar: some View {
        VStack(spacing: 17) {
            HStack(spacing: 16) {
                Button(action: paste) { Label("Pegar enlace", systemImage: "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 11).foregroundStyle(.white).background(palette.accent, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).disabled(store.isProbing)
                Picker("Formato", selection: $store.format) { ForEach(DownloadFormat.allCases) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 125)
                Picker("Calidad", selection: $store.quality) { ForEach(VideoQuality.allCases) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 145).disabled(store.format == .audio)
                Spacer()
                Menu {
                    Button("Descargar canal…") { channelMode = true; showInput = true; updateLink("") }.disabled(store.isProbing)
                    Button("Elegir carpeta…") { store.chooseFolder() }
                } label: { Label("Avanzado", systemImage: "slider.horizontal.3").font(.system(size: 12)) }.menuStyle(.borderlessButton).frame(width: 110)
            }
            if showInput { inlineInput }
            HStack(spacing: 22) {
                Toggle("Metadatos .txt", isOn: $store.options.metadata).help("Guardar descripción y metadatos junto a cada video")
                Toggle("Fecha en nombre", isOn: $store.options.publicationDate).help("Anteponer la fecha de publicación, o la de subida si no está disponible")
                Toggle("Dividir capítulos", isOn: $store.options.splitChapters).help("Guardar un archivo por capítulo y conservar el video completo")
                Spacer()
            }.toggleStyle(.checkbox).font(.system(size: 11))
        }.padding(.horizontal, 28).padding(.vertical, 22).background(palette.surface)
    }
    private func paste() {
        channelMode = false
        showInput = true
        updateLink(NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if validLink { Task { await analyze() } }
        else { probeError = "El portapapeles no contiene un enlace válido." }
    }
    private var candidateList: String? { URL(string: link).flatMap { DownloadCommand.playlistURL(for: $0) } }
    private var playlistOnly: Bool { preview?.isCollection == true || URL(string: link)?.path == "/playlist" }
    private var validLink: Bool {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }
    private var inlineInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if store.isProbing { ProgressView().controlSize(.small); Text("Analizando…") }
                else if let error = probeError { Text(error).foregroundStyle(.red).lineLimit(3).textSelection(.enabled) }
                else if let preview { Image(systemName: "checkmark.circle").foregroundStyle(palette.accent); Text(preview.title).lineLimit(1) }
                else { Text(channelMode ? "Enlace del canal" : "Enlace del video").foregroundStyle(.secondary) }
                Spacer()
                Button { showInput = false; updateLink("") } label: { Image(systemName: "xmark") }.buttonStyle(.plain).disabled(store.isProbing).help("Cerrar análisis")
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                TextField(channelMode ? "https://www.youtube.com/@canal" : "https://…", text: Binding(get: { link }, set: updateLink)).textFieldStyle(.roundedBorder).disabled(store.isProbing).onSubmit { Task { await analyze() } }
                Button("Analizar") { Task { await analyze() } }.disabled(!validLink || store.isProbing)
                Button(channelMode ? "Descargar canal" : "Descargar", action: download).buttonStyle(.borderedProminent).disabled(!validLink || store.isProbing || (channelMode && preview?.isCollection != true))
            }
            if !channelMode, candidateList != nil || playlistOnly {
                Picker("Descargar", selection: $scope) {
                    if !playlistOnly { Text("Solo este video").tag(DownloadScope.video) }
                    Text("Lista completa").tag(DownloadScope.playlist)
                }.pickerStyle(.segmented).frame(maxWidth: 330)
            }
            if let preview, store.options.splitChapters, !preview.isCollection {
                Text(preview.chapters.isEmpty ? "Sin capítulos; se guardará el archivo completo." : "\(preview.chapters.count) capítulos").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func updateLink(_ value: String) {
        link = value.trimmingCharacters(in: .whitespacesAndNewlines)
        preview = nil; probeError = nil
        scope = channelMode ? .channel : playlistOnly ? .playlist : .video
    }
    private func analyze() async {
        let selectedLink = link
        let result = await store.inspect(url: selectedLink, channel: channelMode)
        guard link == selectedLink else { return }
        preview = result; probeError = store.error; store.error = nil
        if !channelMode, result?.isCollection == true { scope = .playlist }
    }
    private func download() {
        var options = store.options; options.scope = scope
        let url = scope == .playlist ? (candidateList ?? preview?.playlistURL ?? link) : link
        store.add(url: url, options: options)
        if let error = store.error { probeError = error; store.error = nil }
        else { showInput = false; updateLink("") }
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    @ObservedObject var store: DownloadStore
    let palette: Palette
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: item.options?.scope == .channel ? "person.crop.rectangle.stack" : item.options?.scope == .playlist ? "list.bullet.rectangle" : item.format == .audio ? "waveform" : "play.rectangle").font(.system(size: 25, weight: .light)).foregroundStyle(palette.accent).frame(width: 47, height: 47).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                HStack(spacing: 9) {
                    Text(item.status.label)
                    if let count = item.completedCount, item.options?.scope != .video { Text("\(count) videos guardados") }
                    if let index = item.collectionIndex { Text("Video \(index)" + (item.collectionCount.map { " / \($0)" } ?? "")) }
                }.font(.system(size: 10)).foregroundStyle(item.status == .failed || item.status == .partial ? .red : .secondary)
                if item.status == .downloading {
                    ProgressView(value: item.progress).tint(palette.accent)
                    HStack { Text("\(Int(item.progress * 100)) %"); Spacer(); Text(item.speed); Text(item.eta) }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let warning = item.warning { Text(warning).font(.system(size: 10)).foregroundStyle(.secondary) }
                if let error = item.error { Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(3).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 15) {
                if item.status == .completed || item.status == .partial { Button { store.reveal(item: item) } label: { Image(systemName: "folder") }.help("Mostrar archivos") }
                if [.failed, .partial, .cancelled].contains(item.status) { Button { store.retry(id: item.id) } label: { Image(systemName: "arrow.clockwise") }.help("Reintentar") }
                if [.queued, .downloading].contains(item.status) { Button { store.cancel(id: item.id) } label: { Image(systemName: "xmark") }.help("Cancelar") }
                else { Button { store.remove(id: item.id) } label: { Image(systemName: "trash") }.help("Quitar del historial") }
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12)).padding(.top, 5)
        }.padding(16).background(palette.surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1))
    }
}
