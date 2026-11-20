import SwiftUI

struct RootView: View {
    var body: some View {
        Text("DeepGlass")
            .font(DS.Typography.title)
            .foregroundStyle(DS.Colors.labelPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Colors.bgBase)
    }
}

#Preview {
    RootView()
}
