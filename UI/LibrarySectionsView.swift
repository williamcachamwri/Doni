import SwiftUI
import Support
import TelegramDesignSystem
import TdSession

/// The listener's own music in one door: the hearts and the lists, as two segments of one screen.
///
/// The reference does exactly this (`ContentView.swift:22-60` — 首页 / 发现 / 音乐库 / 设置), and the
/// reason is not tidiness. iOS 26 only lets the search tab keep its own circle outside the pill while
/// the bar has four items to show; every tab added pushes the fifth into an overflow, and the overflow
/// is what swallowed the search circle. Two doors that answer the same question — "what have I kept" —
/// belong behind one, with the segment saying which half.
struct LibrarySectionsView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var segment: Segment = .liked

    enum Segment: String, CaseIterable, Identifiable {
        case liked
        case lists

        var id: Self { self }

        var title: String {
            switch self {
            case .liked: "Yêu thích"
            case .lists: "Danh sách"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Phần thư viện", selection: $segment) {
                ForEach(Segment.allCases) { part in
                    Text(LocalizedStringKey(part.title)).tag(part)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, MusicExploreMetrics.gutter)
            .padding(.vertical, 8)

            Group {
                switch segment {
                case .liked:
                    LikesView(session: session, player: player, artwork: artwork,
                              library: library)
                case .lists:
                    PlaylistsView(session: session, player: player, artwork: artwork,
                                  library: library)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Thư viện")
    }
}
