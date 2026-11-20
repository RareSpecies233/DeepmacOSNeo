import SwiftUI

#if canImport(AppKit)
import AppKit
typealias MarkdownPlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias MarkdownPlatformImage = UIImage
#endif

extension MarkdownPlatformImage {
    /// 把快照图片塞进 `Text` 行内流（用于行内公式）。
    var markdownInlineText: Text {
        #if canImport(AppKit)
        Text(Image(nsImage: self))
        #else
        Text(Image(uiImage: self))
        #endif
    }
}

extension Image {
    init(markdownPlatformImage: MarkdownPlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: markdownPlatformImage)
        #else
        self.init(uiImage: markdownPlatformImage)
        #endif
    }
}

extension MarkdownPlatformImage {
    static func markdownImage(contentsOf url: URL) -> MarkdownPlatformImage? {
        #if canImport(AppKit)
        return NSImage(contentsOf: url)
        #else
        return UIImage(contentsOfFile: url.path)
        #endif
    }
}
