import SwiftUI
import Support

struct LyricsShareExperienceView: View {
    @State private var store: LyricShareSelectionStore

    init(presentation: LyricSharePresentation) {
        _store = State(
            initialValue: LyricShareSelectionStore(
                presentation: presentation
            )
        )
    }

    var body: some View {
        LyricsSelectionView(store: store)
        .task(id: store.presentation.song.album?.artworkURL) {
            await loadArtwork()
        }
    }

    private func loadArtwork() async {
        guard store.artwork == nil,
              let url = store.presentation.song.album?.artworkURL else {
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, let image = DoniImage(data: data) else { return }
            store.artwork = image
        } catch {
            return
        }
    }
}
