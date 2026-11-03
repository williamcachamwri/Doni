import SwiftUI
import TelegramDesignSystem
import TdSession

/// Login: one screen per authorization state, driven by TDLib's state rather than by a step
/// counter, so a session that resumes at the code step or at the password step shows the right
/// field without extra bookkeeping.
///
/// The layout follows `Docs/design-tokens.md`, "Login (authorization sequence)": white background,
/// measured type, ruled fields, a capsule button 24 pt above the keyboard, and content hanging
/// from the top with its gaps stretching to their maxima, which is how `layoutAuthorizationItems`
/// distributes the space a screen leaves over.
struct LoginView: View {
    @ObservedObject var session: TelegramSession
    @State private var country = DialCountry.current()
    @State private var nationalNumber = ""
    @State private var code = ""
    @State private var password = ""
    @State private var isKeyboardVisible = false

    private let list = TelegramListPalette.day

    var body: some View {
        ZStack {
            list.background.ignoresSafeArea()

            GeometryReader { proxy in
                content(screenWidth: proxy.size.width)
            }
        }
        .on(UIApplication.keyboardWillShowNotification) { isKeyboardVisible = true }
        .on(UIApplication.keyboardWillHideNotification) { isKeyboardVisible = false }
        .task { session.start() }
    }

    private func content(screenWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            gap(TelegramLoginMetrics.topInset)

            Text(title)
                .font(titleFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(list.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            gap(TelegramLoginMetrics.titleToSubtitle)

            Text(subtitle)
                .font(TelegramLoginTypography.subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(list.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            fieldGap
            field(screenWidth: screenWidth)

            if let message = session.lastError {
                Text(message)
                    .font(TelegramLoginTypography.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(list.destructive)
                    .padding(.top, 11)
            }

            if let resend = resendTitle {
                gap(TelegramLoginMetrics.fieldToResend, maximum: 120)
                Button(action: { session.resendCode() }) {
                    Text(resend)
                        .font(TelegramLoginTypography.link)
                        .foregroundStyle(session.isWaiting ? list.disabledText : list.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(session.isWaiting)
            }

            Spacer(minLength: 0)

            TelegramPrimaryButton(
                palette: list,
                title: buttonTitle,
                isBusy: session.isWaiting,
                isEnabled: canContinue,
                action: submit
            )
        }
        .padding(.horizontal, TelegramLoginMetrics.horizontalInset)
        .padding(.bottom, TelegramLoginMetrics.buttonToBottom)
    }

    /// Telegram keeps the title at 30 light until the keyboard takes the lower half of the
    /// screen, then swaps it for 28 bold instead of pushing it up.
    private var titleFont: Font {
        if isPhoneStep {
            return isKeyboardVisible
                ? TelegramLoginTypography.phoneTitleActive
                : TelegramLoginTypography.phoneTitleIdle
        }
        return TelegramLoginTypography.title
    }

    private var isPhoneStep: Bool {
        switch session.step {
        case .waitPhoneNumber?, nil:
            return true
        default:
            return false
        }
    }

    private var title: String {
        switch session.step {
        case .waitPhoneNumber?, nil:
            "Số điện thoại của bạn"
        case .waitCode(_, let current, _, _):
            switch current.lengthOfCode {
            case let length?: "Nhập mã \(length) chữ số"
            case nil: "Nhập mã xác nhận"
            }
        case .waitPassword?:
            "Xác thực hai bước"
        case .waitOtherDeviceConfirmation?:
            "Xác nhận trên thiết bị khác"
        case .waitRegistration?:
            "Cần đăng ký tài khoản"
        case .ready?:
            ""
        case .loggingOut?, .closing?, .closed?:
            "Đang đăng xuất…"
        case .waitTdlibParameters?:
            "Đang chuẩn bị…"
        case .unknown(let type)?:
            type
        }
    }

    private var subtitle: String {
        switch session.step {
        case .waitPhoneNumber?, nil:
            "Nhập số điện thoại của bạn để tiếp tục."
        case .waitCode(let sentTo, let current, _, _):
            switch current {
            case .smsWord(let letter):
                "Nhập từ bắt đầu bằng “\(letter)” mà chúng tôi đã gửi cho \(sentTo)."
            case .smsPhrase(let word):
                "Nhập câu bắt đầu bằng “\(word)” mà chúng tôi đã gửi cho \(sentTo)."
            default:
                switch current.lengthOfCode {
                case let length?: "Chúng tôi đã gửi mã \(length) chữ số cho \(sentTo)."
                case nil: "Chúng tôi đã gửi mã cho \(sentTo)."
                }
            }
        case .waitPassword(let hint, _, _):
            hint.isEmpty ? "Nhập mật khẩu bạn đã đặt cho tài khoản này." : "Gợi ý: \(hint)"
        case .waitRegistration(let minimumAge)?:
            "Số này chưa có tài khoản Telegram và cần đủ \(minimumAge) tuổi."
        case .waitOtherDeviceConfirmation(let link)?:
            link
        case .ready?, .loggingOut?, .closing?, .closed?, .waitTdlibParameters?, .unknown?:
            ""
        }
    }

    /// 30 pt is the phone screen's fixed gap; the code and password screens let theirs stretch,
    /// up to the maxima Telegram caps them at.
    @ViewBuilder private var fieldGap: some View {
        switch session.step {
        case .waitPhoneNumber?, nil:
            gap(TelegramLoginMetrics.subtitleToField)
        case .waitCode?:
            gap(TelegramLoginMetrics.subtitleToField, maximum: 100)
        case .waitPassword?:
            gap(32, maximum: 60)
        default:
            gap(0)
        }
    }

    @ViewBuilder private func field(screenWidth: CGFloat) -> some View {
        switch session.step {
        case .waitPhoneNumber?, nil:
            PhoneNumberField(palette: list, country: $country, nationalNumber: $nationalNumber)
        case .waitCode(_, let current, _, _):
            switch current.lengthOfCode {
            case let length?:
                CodeBoxes(
                    palette: list,
                    length: length,
                    isCompact: screenWidth <= 320 || (screenWidth <= 375 && length > 5),
                    text: $code
                )
            case nil:
                UnderlineField(palette: list, placeholder: current.placeholder, text: $code)
            }
        case .waitPassword?:
            UnderlineField(palette: list, placeholder: "Mật khẩu", text: $password, isSecure: true)
        default:
            EmptyView()
        }
    }

    private var buttonTitle: String {
        switch session.step {
        case .waitPassword?: "Đăng nhập"
        default: "Tiếp tục"
        }
    }

    private var resendTitle: String? {
        guard case .waitCode(_, _, let next, _)? = session.step, next != nil else { return nil }
        return "Gửi lại mã"
    }

    private var canContinue: Bool {
        switch session.step {
        case .waitPhoneNumber?, nil:
            nationalNumber.contains { $0.isNumber }
        case .waitCode?:
            !code.isEmpty
        case .waitPassword?:
            !password.isEmpty
        default:
            false
        }
    }

    private func submit() {
        switch session.step {
        case .waitPhoneNumber?, nil:
            session.submitPhoneNumber(country.dialCode + String(nationalNumber.filter { $0.isNumber }))
        case .waitCode?:
            session.submitCode(code)
        case .waitPassword?:
            session.submitPassword(password)
        default:
            break
        }
    }

    private func gap(_ height: CGFloat, maximum: CGFloat? = nil) -> some View {
        Color.clear.frame(minHeight: height, maxHeight: maximum ?? height)
    }
}

extension TdAuthorizationStep.CodeDelivery {
    /// Digit count for the box row, `nil` when Telegram asked for a word or a phrase instead,
    /// which a number pad cannot type.
    var lengthOfCode: Int? {
        switch self {
        case .telegramMessage(let length), .sms(let length), .call(let length):
            length
        case .missedCall(_, let length):
            length
        case .smsWord, .smsPhrase, .flashCall, .unknown:
            nil
        }
    }

    var placeholder: String {
        switch self {
        case .smsWord(let letter):
            "Từ bắt đầu bằng \(letter)"
        case .smsPhrase(let word):
            "Câu bắt đầu bằng \(word)"
        default:
            "Mã"
        }
    }
}

private extension View {
    func on(_ notification: Notification.Name, perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: notification)) { _ in action() }
    }
}
