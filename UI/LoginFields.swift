import SwiftUI
import TelegramDesignSystem

/// The input pieces the authorization screens are made of, drawn from the numbers in
/// `Docs/design-tokens.md` ("Login (authorization sequence)"). Telegram draws these fields
/// as rules rather than boxes, so most of what is here is a hairline in the right place.

struct LoginHairline: View {
    let color: Color
    var displayScale: CGFloat

    var body: some View {
        color
            .frame(height: TelegramGeometry.hairline(displayScale: displayScale))
            .frame(maxWidth: .infinity)
    }
}

/// A dial code plus the name it belongs to. Names are taken from `Locale`, so they follow
/// the device language instead of being hard-coded English labels.
struct DialCountry: Identifiable, Hashable {
    let isoCode: String
    let dialCode: String

    var id: String { "\(isoCode)\(dialCode)" }

    var name: String {
        Locale.current.localizedString(forRegionCode: isoCode) ?? isoCode
    }

    static let all: [DialCountry] = [
        .init(isoCode: "VN", dialCode: "+84"),
        .init(isoCode: "US", dialCode: "+1"),
        .init(isoCode: "CA", dialCode: "+1"),
        .init(isoCode: "GB", dialCode: "+44"),
        .init(isoCode: "AU", dialCode: "+61"),
        .init(isoCode: "FR", dialCode: "+33"),
        .init(isoCode: "DE", dialCode: "+49"),
        .init(isoCode: "JP", dialCode: "+81"),
        .init(isoCode: "KR", dialCode: "+82"),
        .init(isoCode: "TH", dialCode: "+66"),
    ]

    static func current() -> DialCountry {
        let region = Locale.current.region?.identifier
        return all.first { $0.isoCode == region } ?? all[0]
    }
}

/// The two-rule phone block: country row, then dial code and number on one row.
struct PhoneNumberField: View {
    @Environment(\.displayScale) private var displayScale
    @FocusState private var isEditing: Bool

    let palette: TelegramListPalette
    @Binding var country: DialCountry
    @Binding var nationalNumber: String
    var isGhost = false

    var body: some View {
        VStack(spacing: 0) {
            LoginHairline(color: palette.separator, displayScale: displayScale)

            Menu {
                ForEach(DialCountry.all) { option in
                    Button(option.name) { country = option }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(country.name)
                        .font(TelegramLoginTypography.field)
                        .foregroundStyle(palette.accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: TelegramLoginMetrics.countryChevronWidth, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Spacer(minLength: 0)
                }
                .padding(.leading, TelegramLoginMetrics.countryLeading - TelegramLoginMetrics.horizontalInset)
                .frame(height: TelegramLoginMetrics.countryRowHeight)
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)

            LoginHairline(color: palette.separator, displayScale: displayScale)

            HStack(spacing: 0) {
                Text(country.dialCode)
                    .font(TelegramLoginTypography.field)
                    .foregroundStyle(palette.primaryText)
                    .frame(
                        width: TelegramLoginMetrics.numberLeading - TelegramLoginMetrics.dialCodeLeading,
                        alignment: .leading
                    )
                TextField("Số điện thoại", text: $nationalNumber)
                    .font(TelegramLoginTypography.field)
                    .foregroundStyle(palette.primaryText)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .autocorrectionDisabled()
                    .focused($isEditing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.leading, TelegramLoginMetrics.dialCodeLeading - TelegramLoginMetrics.horizontalInset)
            .frame(height: TelegramLoginMetrics.numberRowHeight)
            .contentShape(Rectangle())
            .onTapGesture { isEditing = true }

            LoginHairline(color: palette.separator, displayScale: displayScale)
        }
        .onAppear { if !isGhost { isEditing = true } }
    }
}

/// A single ruled field, used for an SMS word or phrase and for the account password.
struct UnderlineField: View {
    @Environment(\.displayScale) private var displayScale
    @FocusState private var isEditing: Bool

    let palette: TelegramListPalette
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var isGhost = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(TelegramLoginTypography.field)
            .foregroundStyle(palette.primaryText)
            .autocorrectionDisabled()
            .focused($isEditing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The rule is 16 pt wider on each side than the text it underlines.
            .padding(.horizontal, 16)
            .frame(height: TelegramLoginMetrics.plainFieldHeight)
            .contentShape(Rectangle())
            .onTapGesture { isEditing = true }

            LoginHairline(color: palette.separator, displayScale: displayScale)
        }
        .onAppear { if !isGhost { isEditing = true } }
    }
}

/// The segmented digit boxes. The real `UITextField` is invisible and sits on top of them:
/// Telegram draws the caret by highlighting the box being filled, not by letting the field
/// show its own.
struct CodeBoxes: View {
    /// `isFailed` and `isSucceeded` recolour *every* border at once, which is how the view
    /// reports a rejected or accepted code before it resets.
    enum Entry: Equatable { case normal, failed, succeeded }

    @Environment(\.displayScale) private var displayScale
    @FocusState private var isEditing: Bool

    let palette: TelegramListPalette
    let length: Int
    var isCompact = false
    var entry: Entry = .normal
    var isGhost = false
    @Binding var text: String

    private var boxWidth: CGFloat {
        isCompact ? TelegramLoginMetrics.codeBoxCompactWidth : TelegramLoginMetrics.codeBoxWidth
    }

    private var boxHeight: CGFloat {
        isCompact ? TelegramLoginMetrics.codeBoxCompactHeight : TelegramLoginMetrics.codeBoxHeight
    }

    var body: some View {
        ZStack {
            HStack(spacing: TelegramLoginMetrics.codeBoxSpacing) {
                ForEach(0..<max(length, 1), id: \.self) { index in
                    box(at: index)
                }
            }
            .animation(TelegramLoginMotion.digitEnter, value: text)
            .animation(TelegramLoginMotion.borderColour, value: entry)
            TextField("", text: $text)
                .font(TelegramLoginTypography.digit)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isEditing)
                // One per cent still paints the digits and the caret: at 23 pt on a black canvas a
                // hundredth of white is a legible ghost of the code, sitting outside the boxes. The
                // text and the tint go clear and the opacity stays, because it is the opacity that
                // keeps the field hit-testable and first responder.
                .foregroundStyle(.clear)
                .tint(.clear)
                // Filling the row is what makes a tap anywhere in the boxes land on the field;
                // at its intrinsic height it would only cover a band through their middle.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.01)
        }
        .frame(height: boxHeight)
        .contentShape(Rectangle())
        .onTapGesture { isEditing = true }
        .onAppear { if !isGhost { isEditing = true } }
        .onChange(of: text) { _, value in
            let digits = String(value.filter { $0.isNumber })
            if digits.count != value.count || digits.count > length {
                text = String(digits.prefix(length))
            }
        }
    }

    @ViewBuilder private func box(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: TelegramLoginMetrics.codeBoxCornerRadius, style: .continuous)
            .strokeBorder(
                border(for: index),
                lineWidth: 1.0 + TelegramGeometry.hairline(displayScale: displayScale)
            )
            .overlay(digit(at: index))
            .frame(width: boxWidth, height: boxHeight)
    }

    @ViewBuilder private func digit(at index: Int) -> some View {
        let characters = Array(text)
        if index < characters.count {
            Text(String(characters[index]))
                .font(isCompact ? TelegramLoginTypography.digitCompact : TelegramLoginTypography.digit)
                .foregroundStyle(palette.primaryText)
                .transition(digitTransition)
        }
    }

    private var digitTransition: AnyTransition {
        let settled = DigitMotion(alpha: 1, scaleY: 1, offset: 0)
        return .asymmetric(
            insertion: .modifier(
                active: DigitMotion(
                    alpha: 0,
                    scaleY: 0.01,
                    offset: boxHeight * TelegramLoginMotion.digitRiseFraction
                ),
                identity: settled
            ),
            removal: .modifier(
                active: DigitMotion(
                    alpha: 0,
                    scaleY: 1,
                    offset: boxHeight * TelegramLoginMotion.digitFallFraction
                ),
                identity: settled
            )
        )
    }

    /// The whole row goes red or green together; in the normal state only the box being
    /// filled carries the accent, which is how the caret is drawn.
    private func border(for index: Int) -> Color {
        switch entry {
        case .failed: return palette.destructive
        case .succeeded: return palette.constructive
        case .normal:
            return index == Array(text).count ? palette.accent : palette.separator
        }
    }
}

/// The filled capsule every authorization screen ends with.
struct TelegramPrimaryButton: View {
    let palette: TelegramListPalette
    let title: String
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: TelegramLoginMetrics.buttonCornerRadius,
                    style: .continuous
                )
                .fill(isEnabled ? palette.checkFill : palette.disabledCheckFill)

                if isBusy {
                    ProgressView()
                        .tint(isEnabled ? palette.checkForeground : palette.disabledText)
                } else {
                    Text(title)
                        .font(TelegramLoginTypography.buttonTitle)
                        .foregroundStyle(isEnabled ? palette.checkForeground : palette.disabledText)
                }
            }
            .frame(height: TelegramLoginMetrics.buttonHeight)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

/// The wrong-code shake. `addShakeAnimation` is a keyframe animation on `position.x` with the
/// keyframes evenly spaced, so the track is sampled from a progress value that the caller
/// animates linearly from 0 to 1 rather than replayed as a SwiftUI keyframe track.
struct LoginShake: GeometryEffect {
    var progress: Double
    let offsets: [CGFloat]

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = TelegramLoginMotion.shakeOffset(at: progress, offsets: offsets)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// A digit rides in from below its own baseline, growing out of the box's bottom edge
/// (`CodeInputView.swift:82-86`), and the one being deleted fades out while it falls half a
/// box (`:90-95`). One modifier because `AnyTransition.modifier` needs both ends of the same
/// type; the ends differ only in their numbers.
private struct DigitMotion: ViewModifier {
    let alpha: Double
    let scaleY: CGFloat
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(alpha)
            .scaleEffect(x: 1.0, y: scaleY, anchor: .bottom)
            .offset(y: offset)
    }
}
