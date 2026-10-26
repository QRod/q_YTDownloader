import AppKit
import Foundation

let history = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/q_YTDownloader/history.json")
if let data = try? Data(contentsOf: history), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let items = value["items"] as? [[String: Any]], items.contains(where: { ["queued", "downloading"].contains($0["status"] as? String ?? "") }) {
    print("Hay descargas activas; la app no se reinició.")
    exit(3)
}
let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else { print("Usage: ReloadPreview <preview executable path> [...]"); exit(2) }
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.q.ytdownloader") {
    guard let path = app.executableURL?.resolvingSymlinksInPath().path, paths.contains(path) else { continue }
    guard app.terminate() else { print("No se pudo cerrar la vista previa anterior."); exit(1) }
    let deadline = Date().addingTimeInterval(5)
    while !app.isTerminated && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    guard app.isTerminated else { print("La vista previa anterior sigue abierta."); exit(1) }
}
print("Vista previa anterior cerrada; no había descargas activas.")
