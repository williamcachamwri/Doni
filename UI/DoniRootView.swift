import SwiftUI
import TelegramDesignSystem

/// M0 harness screen: proves the design-system package is linked and that the
/// extracted tokens survive into SwiftUI. Replaced by the channel list in M2.
struct DoniRootView: View {
    private let palette = TelegramPalette.day

    var body: some View {
        NavigationStack {
            List {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.accent)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Doni")
                            .foregroundStyle(palette.chatListTitle)
                        Text("design tokens wired")
                            .font(.footnote)
                            .foregroundStyle(palette.chatListMessageText)
                    }
                }
            }
            .listRowBackground(palette.chatListBackground)
            .scrollContentBackground(.hidden)
            .background(palette.chatListBackground)
            .navigationTitle("Doni")
        }
    }
}

#Preview {
    DoniRootView()
}
