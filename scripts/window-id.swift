import CoreGraphics
import Foundation

// 用法: swift scripts/window-id.swift <AppName>
let target = CommandLine.arguments.dropFirst().first ?? "DeepGlass"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
var best: (id: Int, area: Double)?
for window in list {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == target,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
          height > 200 else { continue }
    let area = width * height
    if best == nil || area > best!.area { best = (number, area) }
}
if let best { print(best.id) } else { exit(1) }
