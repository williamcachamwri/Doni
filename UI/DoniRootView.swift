import SwiftUI
import TelegramDesignSystem
import TdBridge

/// M0 harness screen: proves the design-system package is linked and that
/// TDLib compiles, links and answers at runtime. Replaced by the channel list
/// in M2.
///
/// `getTextEntities` is one of the requests documented as callable
/// synchronously, so it exercises the real library without a session, an
/// api_id or any network — if this renders TDLib's version, the xcframework is
/// wired correctly end to end.
struct DoniRootView: View {
    private let palette = TelegramPalette.day
    @ObservedObject var session: TelegramSession
    @State private var transport: String = "checking tdlib…"

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
                        Text(transport)
                            .font(.footnote)
                            .foregroundStyle(palette.chatListMessageText)
                    }
                }

                Button("Đăng xuất", role: .destructive) { session.logOut() }
            }
            .listRowBackground(palette.chatListBackground)
            .scrollContentBackground(.hidden)
            .background(palette.chatListBackground)
            .navigationTitle("Doni")
            .task { transport = TdTransport.probe() }
        }
    }
}

#Preview {
    DoniRootView(session: TelegramSession())
}
