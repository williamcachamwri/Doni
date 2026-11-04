import SwiftUI
import AVFoundation
import MediaPlayer
import Support
import TelegramDesignSystem

/// The full player the strip opens, drawn to the Apple Music kit the user pointed at —
/// `AMNowPlayingViewController.swift` and its `ControlsView`, number for number: a 36×5 grip
/// 6 pt under the safe area, the cover a width less 2 × 24 with a 10 pt corner and a 100 pt
/// shadow hanging 30 under the grip, and the controls inset 32, starting 52.66 under the cover
/// and ending 18 above the safe bottom, their rows 32.66 apart.
///
/// What the kit does not have is Doni's: the star, the cut menu, the times under the scrubber,
/// and a lower slider that actually moves the device's volume — the kit's is a prop, so Doni's
/// drives a hidden `MPVolumeView` and reads it back twice a second for the hardware keys.
///
/// The motion is still Telegram's (`TelegramShellMotion`) where the kit is silent: the 0.15 s
/// crossfade on a track change, the words pushing up from the bottom, `replace.downUp` on the
/// play glyph, and the badge spring under every button. The screen closes the way the kit's
/// does — a tap on the grip, or a drag down that the shell rises with.
struct NowPlayingView: View {
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// The artwork morphs out of the strip's 40 pt corner, so this panel owns the geometry
    /// source while it is up.
    let namespace: Namespace.ID
    /// How far down the panel is being dragged, 0…1, read by the shell to rise underneath.
    @Binding var dragProgress: CGFloat
    let close: () -> Void

    /// Where the finger is holding the scrubber, which is not where the song is.
    @GestureState private var scrubProgress: Double?
    /// The start of a cut the user is marking, before they have reached its end.
    @State private var markIn: Double?
    /// The panel's own offset while a drag down is in progress; zero when it rests.
    @State private var panOffset: CGFloat = 0
    /// The device's volume, 0…1 — written by the visible bar, read back from the hardware.
    @State private var volumeLevel = Double(AVAudioSession.sharedInstance().outputVolume)
    /// The backdrop's two stops, taken from the artwork the way the kit's gradient takes its own
    /// (`AMNowPlayingViewController.swift:46`).
    @State private var backdropTop = Color(rgb: 0x3e3e40)
    @State private var backdropBottom = Color.black

    private let palette = TelegramPalette.dark

    var body: some View {
        GeometryReader { edge in
            ZStack {
                backdrop
                VStack(spacing: 0) {
                    grip
                        .padding(.top, 6)
                    art
                        .padding(.top, 30)
                        .padding(.horizontal, 24)
                    controls
                        .padding(.top, 52.66)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 18)
                }
            }
            .offset(y: max(0, panOffset))
            .gesture(pan(height: edge.size.height))
        }
        .preferredColorScheme(.dark)
        .task(id: player.current?.uniqueId) { refreshBackdrop() }
        .onReceive(artwork.objectWillChange) { _ in
            Task { @MainActor in refreshBackdrop() }
        }
        .background {
            VolumeSurface(level: $volumeLevel)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// The kit's gradient: the artwork's average colour at the top and a third-and-a-bit of it
    /// at the bottom (`AMNowPlayingViewController.swift:46` feeds two stops to a vertical
    /// `CAGradientLayer`).
    private var backdrop: some View {
        LinearGradient(colors: [backdropTop, backdropBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(TelegramShellMotion.crossfade, value: player.current?.uniqueId)
    }

    /// Reads the current artwork's average and re-tints the two stops; a track with no artwork
    /// keeps the placeholder pair it opened with.
    private func refreshBackdrop() {
        guard let track = player.current,
              let colours = Self.gradientColours(artwork.image(for: track)) else { return }
        backdropTop = colours.top
        backdropBottom = colours.bottom
    }

    /// One pixel of CIAreaAverage over the artwork, in sRGB.
    private static func gradientColours(_ image: UIImage?) -> (top: Color, bottom: Color)? {
        guard let image, let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        return (Color(.sRGB, red: red, green: green, blue: blue),
                Color(.sRGB, red: red * 0.35, green: green * 0.35, blue: blue * 0.35))
    }

    /// The kit's only chrome: a 36×5 white-at-a-half handle 6 pt under the safe area
    /// (`AMGripView.swift`), which dismisses on a tap the way the kit's does
    /// (`AMNowPlayingViewController.swift:73-75`).
    private var grip: some View {
        Capsule()
            .fill(Color.white.opacity(0.5))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityLabel("Đóng")
    }

    /// The kit's cover: a square the width of the screen less 2 × 24, a 10 pt continuous corner,
    /// and a 100 pt shadow at half black that lifts it off its own gradient
    /// (`AMNowPlayingViewController.swift:85-88`, `AMArtworkView.swift`). The strip's 40 pt
    /// corner morphs into this.
    @ViewBuilder
    private var art: some View {
        if let track = player.current {
            ZStack {
                TelegramTrackGradient.linear(track.messageId)
                if let image = artwork.image(for: track) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 100)
            .matchedGeometryEffect(id: "player-art", in: namespace, isSource: true)
            .animation(TelegramShellMotion.crossfade, value: player.current?.uniqueId)
        }
    }

    private var controls: some View {
        VStack(spacing: 32.66) {
            words
            middle
                .frame(maxHeight: .infinity)
            bottomRow
        }
    }

    /// The kit's title row — `.title3` semibold over plain `.title3`, white, leading — with
    /// Doni's star and cut menu at the trailing edge, dressed as plainly as the kit dresses its
    /// own buttons.
    @ViewBuilder
    private var words: some View {
        if let track = player.current {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                favoriteButton(track)
                cutMenu
            }
            .id(track.uniqueId)
            .transition(.push(from: .bottom))
        }
    }

    /// The star: white outline while a song is only playing, filled once it is kept.
    private func favoriteButton(_ track: any Playable) -> some View {
        let kept = library.favorites.contains { $0.id == track.uniqueId }
        return Button {
            library.toggleFavorite(track)
        } label: {
            Image(systemName: kept ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerButtonStyle())
        .symbolEffect(.bounce, value: kept)
        .accessibilityLabel(kept ? "Bỏ yêu thích" : "Yêu thích")
    }

    /// The cut lives in a menu because the kit's layout has no room for a fourth control, and a
    /// cut is a three-step choice (start, end, keep, or let go), which a menu states better than
    /// a toggle does.
    private var cutMenu: some View {
        Menu {
            if let started = markIn {
                Button("Kết thúc cắt tại \(clock(player.elapsed))") {
                    guard player.elapsed > started else { return }
                    player.segment = started...player.elapsed
                    markIn = nil
                }
            } else if player.segment == nil {
                Button("Bắt đầu cắt tại \(clock(player.elapsed))") {
                    markIn = player.elapsed
                }
            }
            if let segment = player.segment {
                Button("Giữ đoạn này") {
                    if let uniqueId = player.current?.uniqueId {
                        library.setSegment(
                            Int(segment.lowerBound)...Int(segment.upperBound),
                            uniqueId: uniqueId)
                    }
                }
                Button("Bỏ cắt", role: .destructive) {
                    player.segment = nil
                    markIn = nil
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(markIn == nil && player.segment == nil
                    ? .white : palette.highlight)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Cắt đoạn")
    }

    /// The kit's middle block — slider, air, transport, air, slider
    /// (`AMControlsView+ControlsView.swift:28-62`) — with Doni's times tucked under the first
    /// slider.
    private var middle: some View {
        VStack(spacing: 0) {
            progressSlider
            times
                .padding(.top, 8)
            Spacer(minLength: 16)
            transport
            Spacer(minLength: 16)
            volumeSlider
        }
    }

    /// The kit's scrubber, `AMSliderView` transcribed: a 7 pt band of thin material with the
    /// played share drawn over it in white at a half, both clipped to a 3.5 pt rectangle —
    /// square ends, no thumb. A drag is held locally and handed to the player once, on lift.
    private var progressSlider: some View {
        GeometryReader { edge in
            let total = max(player.duration, 1)
            let shown = min(max(scrubProgress ?? player.elapsed / total, 0), 1)
            let width = max(edge.size.width, 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: width * shown)
                    .animation(.linear(duration: 0.25), value: player.elapsed)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            .frame(width: edge.size.width, height: edge.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($scrubProgress) { value, state, _ in
                        state = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        player.seek(to: min(max(value.location.x / width, 0), 1) * total)
                    }
            )
        }
        .frame(height: 7)
    }

    /// Elapsed at the left, what is left of the song at the right with its minus sign. The
    /// centre slot carries the cut instead: its range while it is held, the moment it starts
    /// from while it is being marked. Both times run on `numericText`, so a second ticks in
    /// rather than blinks in.
    private var times: some View {
        HStack {
            Text(MediaClock.duration(Int(player.elapsed.rounded())) ?? "0:00")
            Spacer()
            cutState
            Spacer()
            Text(remaining)
        }
        .font(TelegramShellTypography.timestamp)
        .foregroundStyle(palette.navSecondaryText)
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.linear(duration: 0.25), value: player.elapsed)
    }

    /// The centre slot only ever holds text, so the two times stay pinned to their edges whether
    /// or not there is a cut — marking one never moves them under the finger.
    @ViewBuilder
    private var cutState: some View {
        if let segment = player.segment {
            Text("\(clock(segment.lowerBound)) – \(clock(segment.upperBound))")
        } else if let started = markIn {
            Text("cắt từ \(clock(started))")
        }
    }

    private var remaining: String {
        let left = max(Int((player.duration - player.elapsed).rounded()), 0)
        guard let text = MediaClock.duration(left) else { return "-0:00" }
        return "-\(text)"
    }

    /// The kit's transport: 30, 50, 30, plain weight, white
    /// (`AMControlsView+ControlsView.swift:36-53`), each on its 64 pt stop. The centre glyph
    /// swaps through `replace.downUp` so the pause drops in from above.
    private var transport: some View {
        HStack(spacing: 0) {
            step(system: "backward.fill", size: 30, enabled: player.hasPrevious,
                 action: player.previous)
            Spacer(minLength: 0)
            step(system: player.isPlaying ? "pause.fill" : "play.fill", size: 50,
                 enabled: player.current != nil, action: player.toggle)
            Spacer(minLength: 0)
            step(system: "forward.fill", size: 30, enabled: player.hasNext, action: player.next)
        }
        .animation(TelegramShellMotion.pop, value: player.isPlaying)
    }

    private func step(system: String, size: CGFloat, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size))
                .foregroundStyle(enabled ? .white : Color.white.opacity(0.3))
                .frame(width: TelegramShellMetrics.transportButton,
                       height: TelegramShellMetrics.transportButton)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .buttonStyle(PlayerButtonStyle())
        .disabled(!enabled)
    }

    /// The kit's lower slider, made real: the same 7 pt band as the scrubber, dragging it moves
    /// the device's volume through the hidden `MPVolumeView` behind this view.
    private var volumeSlider: some View {
        GeometryReader { edge in
            let width = max(edge.size.width, 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: width * min(max(volumeLevel, 0), 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            .frame(width: edge.size.width, height: edge.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        volumeLevel = min(max(value.location.x / width, 0), 1)
                    }
            )
        }
        .frame(height: 7)
    }

    /// The kit's three resting glyphs along the bottom — `.title3` semibold, white, inset 52
    /// (`AMControlsView+ControlsView.swift:64-84`). Doni has no lyrics, AirPlay screen or queue
    /// screen behind them yet, so they sit as the kit draws them — at rest.
    private var bottomRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "quote.bubble")
                .frame(maxWidth: .infinity)
            Image(systemName: "airplayaudio")
                .frame(maxWidth: .infinity)
            Image(systemName: "list.bullet")
                .frame(maxWidth: .infinity)
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 52)
    }

    /// The kit's dismissal by hand: the panel follows the finger down one to one while the
    /// shell — which reads `dragProgress` — rises underneath, and past 120 pt it goes
    /// (`AMNowPlayingAnimationController.swift:224-238`), otherwise it springs home in 0.4 s
    /// (`:267`).
    private func pan(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                let translation = value.translation
                guard translation.height > 0,
                      translation.height > abs(translation.width) else { return }
                panOffset = translation.height
                dragProgress = min(translation.height / max(height, 1), 1)
            }
            .onEnded { value in
                let translation = value.translation
                if translation.height > 120, translation.height > abs(translation.width) {
                    close()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                        panOffset = 0
                        dragProgress = 0
                    }
                }
            }
    }

    private func clock(_ seconds: Double) -> String {
        MediaClock.duration(Int(seconds.rounded())) ?? "0:00"
    }
}

/// Telegram's press state: the button dips to 0.82 on a spring that overshoots a little on the
/// way back up, the way `ChatListBadgeNode`'s own scale eases.
struct PlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The hidden half of the volume bar: an `MPVolumeView` parked off screen, whose slider is the
/// one public handle on the device's volume. The visible bar writes into it through
/// `updateUIView`; a twice-a-second read brings hardware-key changes back out.
private struct VolumeSurface: UIViewRepresentable {
    @Binding var level: Double

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -400, y: -400, width: 100, height: 40))
        context.coordinator.poll(view)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        let coordinator = context.coordinator
        coordinator.level = level
        coordinator.binding = $level
        coordinator.push(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var level: Double = 0
        var binding: Binding<Double>?
        /// The last value this side wrote, so the poll can tell its own echo from the
        /// hardware's hand.
        private var lastWritten: Double = -1

        /// Push the visible bar's value into the system slider.
        func push(_ view: MPVolumeView) {
            guard let slider = Self.slider(in: view) else { return }
            if abs(Double(slider.value) - level) > 0.001,
               abs(level - lastWritten) > 0.001 {
                slider.setValue(Float(level), animated: false)
                lastWritten = level
            }
        }

        /// Read the system slider twice a second; a value that neither the bar wrote nor this
        /// side echoed came from the hardware keys.
        func poll(_ view: MPVolumeView) {
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self, let slider = Self.slider(in: view) else { continue }
                    let read = Double(slider.value)
                    if abs(read - level) > 0.001, abs(read - lastWritten) > 0.001 {
                        level = read
                        lastWritten = read
                        binding?.wrappedValue = read
                    }
                }
            }
        }

        private static func slider(in root: UIView) -> UISlider? {
            for subview in root.subviews {
                if let slider = subview as? UISlider { return slider }
                if let found = slider(in: subview) { return found }
            }
            return nil
        }
    }
}
