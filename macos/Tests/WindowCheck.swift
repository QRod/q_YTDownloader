import AppKit
import CoreGraphics
import Foundation
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.q.ytdownloader")
guard let app = apps.first else { print("App is not running"); exit(1) }
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let selected = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
let result: [String: Any] = ["pid": app.processIdentifier, "windows": selected.map { ["id": $0[kCGWindowNumber as String] ?? 0, "name": $0[kCGWindowName as String] ?? "", "bounds": $0[kCGWindowBounds as String] ?? [:]] }]
let data = try JSONSerialization.data(withJSONObject: result)
print(String(decoding: data, as: UTF8.self))
