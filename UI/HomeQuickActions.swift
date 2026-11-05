import SwiftUI
import TelegramDesignSystem

/// The row of gradient tiles at the head of the feed, in the form MeloX ships: `compactHomeQuickActions`
/// defaults to *true* (`AppSettings.swift:1799-1801`), so the tile is the 132 pt one — glyph, spacer,
/// two lines of copy, all of it white on a diagonal gradient, 14 pt of padding inside a 14 pt corner
/// and at most 230 pt wide (`HomeComponents.swift:25-54`, `HomeQuickActionsView.swift:107-146`).
///
/// What the six tiles *are* is Doni's own: MeloX's are Netease recommendations, and this app's
/// library is one Telegram channel. The count is MeloX's, and so is the mix — three of the six open
/// a screen, three start playing (`HomeQuickActionsView.swift:149-158`).
struct HomeQuickActions: View {
    let subtitle: (DoniHomeAction) -> String
    let perform: (DoniHomeAction) -> Void

    @ScaledMetric(relativeTo: .body) private var compactWidth = MusicQuickActionMetrics.compactWidth

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: MusicQuickActionMetrics.gap) {
                ForEach(DoniHomeAction.allCases) { action in
                    Button {
                        perform(action)
                    } label: {
                        tile(action)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        min(length, compactWidth)
                    }
                    .accessibilityHint(localized("Mở %@", action.title))
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, MusicQuickActionMetrics.gap, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private func tile(_ action: DoniHomeAction) -> some View {
        VStack(alignment: .leading, spacing: MusicQuickActionMetrics.textSpacing) {
            Image(systemName: action.systemImage)
                .font(.title2.weight(.semibold))
                .accessibilityHidden(true)

            Spacer(minLength: MusicQuickActionMetrics.glyphToTitle)

            Text(LocalizedStringKey(action.title))
                .font(.headline)
                .lineLimit(2)

            Text(subtitle(action))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(MusicQuickActionMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: MusicQuickActionMetrics.compactHeight)
        .background {
            LinearGradient(colors: action.colors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: MusicQuickActionMetrics.radius))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The six, in the order they appear, each wearing one of MeloX's gradient pairs in MeloX's own
/// sequence (`HomeQuickActionsView.swift:81-96`).
enum DoniHomeAction: String, CaseIterable, Identifiable {
    case shuffle
    case newest
    case likes
    case offline
    case lists
    case resume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shuffle: return "Ngẫu nhiên"
        case .newest: return "Mới nhất"
        case .likes: return "Yêu thích"
        case .offline: return "Nghe offline"
        case .lists: return "Danh sách"
        case .resume: return "Nghe tiếp"
        }
    }

    var systemImage: String {
        switch self {
        case .shuffle: return "shuffle"
        case .newest: return "sparkles"
        case .likes: return "heart.fill"
        case .offline: return "arrow.down.circle.fill"
        case .lists: return "music.note.list"
        case .resume: return "play.circle.fill"
        }
    }

    /// The pairs are the reference's, in the reference's order: pink/red, orange/red, pink/purple,
    /// indigo/purple, cyan/blue, mint/teal.
    var colors: [Color] {
        let pair = MusicQuickActionMetrics.gradientPairs[
            DoniHomeAction.allCases.firstIndex(of: self) ?? 0
        ]
        return [pair.from, pair.to]
    }
}
