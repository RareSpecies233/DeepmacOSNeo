import SwiftUI

/// 把内容限制在消息列宽度内并水平居中。
/// 内边距由调用方负责（消息列与输入框都先加 padding，再套本修饰符）。
struct CenteredColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension View {
    func centeredColumn() -> some View { modifier(CenteredColumn()) }
}
