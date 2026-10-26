import SwiftUI
import AppKit

@main struct InterfacePreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = DownloadStore(storageRoot: URL(fileURLWithPath: "/private/tmp/q-ui-preview-history"))
        store.items = []
        for theme in AppTheme.allCases {
            let view = ContentView(store: store, previewTheme: theme).environment(\.colorScheme, theme.scheme).frame(width: 1010, height: 690)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1010, height: 690)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
            let path = output.appendingPathComponent(theme.rawValue + ".png")
            try png.write(to: path)
            print(path.path)
            window.orderOut(nil)
        }
    }
}
