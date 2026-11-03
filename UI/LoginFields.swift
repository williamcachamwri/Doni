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
            .frame(height: TelegramLoginMetrics.hairline(displayScale: displayScale))
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

    let palette: TelegramListPalette
    @Binding var country: DialCountry
    @Binding var nationalNumber: String

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
            }
            .padding(.leading, TelegramLoginMetrics.dialCodeLeading - TelegramLoginMetrics.horizontalInset)
            .frame(height: TelegramLoginMetrics.numberRowHeight)

            LoginHairline(color: palette.separator, displayScale: displayScale)
        }
    }
}

/// A single ruled field, used for an SMS word or phrase and for the account password.
struct UnderlineField: View {
    @Environment(\.displayScale) private var displayScale

    let palette: TelegramListPalette
    let placeholder: String
    @Binding var text: String
    var isSecure = false

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
            // The rule is 16 pt wider on each side than the text it underlines.
            .padding(.horizontal, 16)
            .frame(height: TelegramLoginMetrics.plainFieldHeight)

            LoginHairline(color: palette.separator, displayScale: displayScale)
        }
    }
}

/// The segmented digit boxes. The real `UITextField` is invisible and sits on top of them:
/// Telegram draws the caret by highlighting the box being filled, not by letting the field
/// show its own.
struct CodeBoxes: View {
    @Environment(\.displayScale) private var displayScale

    let palette: TelegramListPalette
    let length: Int
    var isCompact = false
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
            TextField("", text: $text)
                .font(TelegramLoginTypography.digit)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .opacity(0.01)
        }
        .frame(height: boxHeight)
        .onChange(of: text) { _, value in
            let digits = String(value.filter { $0.isNumber })
            if digits.count != value.count || digits.count > length {
                text = String(digits.prefix(length))
            }
        }
    }

    @ViewBuilder private func box(at index: Int) -> some View {
        let characters = Array(text)
        let digit = index < characters.count ? String(characters[index]) : ""
        let isActive = index == characters.count
        RoundedRectangle(cornerRadius: TelegramLoginMetrics.codeBoxCornerRadius, style: .continuous)
            .strokeBorder(
                isActive ? palette.accent : palette.separator,
                lineWidth: 1.0 + TelegramLoginMetrics.hairline(displayScale: displayScale)
            )
            .overlay(
                Text(digit)
                    .font(isCompact ? TelegramLoginTypography.digitCompact : TelegramLoginTypography.digit)
                    .foregroundStyle(palette.primaryText)
            )
            .frame(width: boxWidth, height: boxHeight)
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
