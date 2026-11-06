import SwiftUI
import TelegramDesignSystem

/// A song's row, at the reference's measurements (`DesktopTrackRow.swift`): a 24-point number that
/// turns into a play glyph under the pointer, 12-point gaps, a 13.5pt title over an 11.5pt performer,
/// a 42-point monospaced duration, and an ellipsis that fades to 0.16 when the row is not being looked
/// at.
///
/// What is Doni's own is the *verb list*. The reference's menu is eleven rows about NetEase — an album
/// page, an artist page, a cloud upload, a stream URL to share — and this app has none of those. What
/// it does have is the phone's own set: keep the song, put it in a list, play it next, put a copy on
/// the machine.
struct DesktopTrackRow: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var library: Library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let track: any Playable
    let index: Int
    let tracks: [any Playable]
    var showsArtwork = false
    var displayNumber: String?
    var onRemove: ((any Playable) -> Void)?

    @State private var isHovered = false
    @State private var namingPlaylist = false
    @State private var playlistName = ""

    private var isCurrent: Bool {
        player.current?.uniqueId == track.uniqueId
    }

    private var isKept: Bool {
        library.isFavorite(track.uniqueId)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(track, in: tracks)
            } label: {
                ZStack {
                    if isHovered || isCurrent {
                        Image(systemName: isCurrent && player.isPlaying
                            ? "waveform" : "play.fill")
                            .foregroundStyle(isCurrent ? MusicTint.accent : Color.primary)
                    } else {
                        Text(displayNumber ?? (index + 1).formatted())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
            }
            .buttonStyle(.plain)
            .help(localized("Phát “%@”", track.displayTitle))

            if showsArtwork {
                DesktopArtworkView(track: track, side: 42, cornerRadius: 6)
                    .frame(width: 42, height: 42)
                    .scaleEffect(isHovered ? 1.025 : 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? MusicTint.accent : Color.primary)
                    .lineLimit(1)
                Text(track.displayPerformer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if track.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Đã tải về máy")
            }

            Text(clock(Double(track.duration ?? 0)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)

            rowMenu
                .opacity(isHovered || isCurrent ? 1 : 0.16)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: showsArtwork ? 54 : 46)
        .background(
            isHovered ? Color.primary.opacity(0.045) : Color.clear,
            in: .rect(cornerRadius: 8)
        )
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .contextMenu { rowMenuContent }
        .alert("Danh sách mới", isPresented: $namingPlaylist) {
            TextField("Tên danh sách", text: $playlistName)
            Button("Tạo") { createPlaylist() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text(localized("“%@” sẽ nằm trong danh sách mới.", track.displayTitle))
        }
    }

    private var rowMenu: some View {
        Menu {
            rowMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var rowMenuContent: some View {
        Button("Phát tiếp theo", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.playNext(track)
        }

        Divider()

        Button(isKept ? "Bỏ yêu thích" : "Yêu thích", systemImage: isKept ? "heart.slash" : "heart") {
            library.toggleFavorite(track)
        }

        if !track.isDownloaded {
            Button("Tải về máy", systemImage: "arrow.down.circle") {
                let sound = player, held = track
                Task { await sound.download(held) }
            }
        }

        Divider()

        ForEach(library.playlists) { list in
            Button(localized("Thêm vào “%@”", list.name)) {
                library.add(track, to: list.id)
            }
        }
        Button("Danh sách mới…", systemImage: "plus") {
            playlistName = ""
            namingPlaylist = true
        }

        if let onRemove {
            Divider()
            Button("Xoá khỏi danh sách", systemImage: "minus.circle", role: .destructive) {
                onRemove(track)
            }
        }
    }

    /// A blank name is refused by the store, so the song only goes in once the list really exists —
    /// the phone's rule, kept.
    private func createPlaylist() {
        guard let created = library.createPlaylist(named: playlistName) else { return }
        library.add(track, to: created.id)
    }

    private func clock(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let seconds = max(Int(time), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
