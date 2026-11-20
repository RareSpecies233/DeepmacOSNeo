import SwiftUI

// MARK: - 文件类型图标

/// 文档图标的类型分组，配色对齐 Reference/chat-demo/src/components/files/FileIcon.tsx。
enum FileIconKind {
    case image
    case pdf
    case table
    case slide
    case other

    init(fileExtension ext: String) {
        switch ext.uppercased() {
        case "JPG", "JPEG", "PNG", "GIF", "WEBP", "BMP", "SVG", "HEIC", "TIF", "TIFF", "AVIF":
            self = .image
        case "PDF":
            self = .pdf
        case "XLS", "XLSX", "CSV", "TSV":
            self = .table
        case "PPT", "PPTX":
            self = .slide
        default:
            self = .other
        }
    }

    /// 图标底色：图片紫、PDF 红、表格绿、PPT 橙、其余蓝（取自参考实现）。
    var color: Color {
        switch self {
        case .image: return Self.rgb(0x8B76F6)
        case .pdf: return Self.rgb(0xEE5138)
        case .table: return Self.rgb(0x3FB67F)
        case .slide: return Self.rgb(0xFB8E34)
        case .other: return Self.rgb(0x418CFF)
        }
    }

    /// hex → sRGB；必须用浮点除法，否则整数相除会被截断成 0（全黑）。
    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text"
        case .table: return "tablecells"
        case .slide: return "chart.bar.doc.horizontal"
        case .other: return "doc.text"
        }
    }
}

/// 28pt 文档图标：彩色纸片 + 折角 + 白色符号。
struct FileIconView: View {
    let kind: FileIconKind
    var size: CGFloat = 28

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(kind.color)

            // 右上折角：白色半透明三角，制造「纸页翻折」的层次
            FoldedCorner()
                .fill(.white.opacity(0.7))
                .frame(width: size * 0.36, height: size * 0.36)

            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 右上角折角三角形。
private struct FoldedCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
