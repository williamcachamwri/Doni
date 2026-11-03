import SwiftUI
import TelegramDesignSystem
import TdSession

/// Login: one screen per authorization state, driven by TDLib's state rather than by a step
/// counter, so a session that resumes at the code step or at the password step shows the right
/// field without extra bookkeeping.
///
/// The layout follows `Docs/design-tokens.md`, "Login (authorization sequence)": white canvas,
/// measured type, ruled fields, a capsule button 24 pt above the keyboard, content hanging from
/// the top with its gaps stretching to their maxima, which is how `layoutAuthorizationItems`
/// distributes the space a screen leaves over.
///
/// The hand-over between two screens is Telegram's snapshot choreography: the outgoing screen is
/// kept on stage as a frozen copy, thrown 100–140 pt up while the field block shrinks to 30 % and
/// both fade out, and the incoming screen fades up over it. The button is the one element that
/// belongs to no screen, so it is hidden in the copy and never fades.
struct LoginView: View {
    @ObservedObject var session: TelegramSession

    @State private var country = DialCountry.current()
    /// The one field on stage: the national number, the code, or the password.
    @State private var entry = ""
    @State private var isKeyboardVisible = false

    @State private var ghost: Ghost?
    @State private var ghostToken = 0
    @State private var ghostTextOffset: CGFloat = 0
    @State private var ghostFieldOffset: CGFloat = 0
    @State private var ghostFieldScale: CGFloat = 1
    @State private var ghostAlpha: Double = 1
    @State private var liveAlpha = 0.0

    @State private var shakeOffsets: [CGFloat] = []
    @State private var shakeProgress = 0.0
    @State private var isCodeFailed = false

    private let list = TelegramListPalette.day

    /// The screen that just left the stage, with everything it was showing.
    private struct Ghost {
        let step: TdAuthorizationStep?
        let entry: String
        let country: DialCountry
    }

    /// Where the frozen copy is in its flight.
    private struct HandOver {
        var textOffset: CGFloat = 0
        var fieldOffset: CGFloat = 0
        var fieldScale: CGFloat = 1
        var alpha: Double = 1
    }

    /// Two updates of the same screen must not replay the hand-over — TDLib resends the code
    /// state when a code is reissued, and Telegram does not animate for that.
    private enum Screen: Equatable {
        case phone, code, password, otherDevice, signUp, ready, busy, other(String)
    }

    var body: some View {
        ZStack {
            list.background.ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    if let ghost {
                        screen(
                            ghost.step,
                            entry: .constant(ghost.entry),
                            country: .constant(ghost.country),
                            screenWidth: proxy.size.width,
                            motion: HandOver(
                                textOffset: ghostTextOffset,
                                fieldOffset: ghostFieldOffset,
                                fieldScale: ghostFieldScale,
                                alpha: ghostAlpha
                            ),
                            isGhost: true
                        )
                        .allowsHitTesting(false)
                    }

                    screen(
                        session.step,
                        entry: $entry,
                        country: $country,
                        screenWidth: proxy.size.width,
                        motion: HandOver(alpha: liveAlpha),
                        isGhost: false
                    )
                }
            }
        }
        .on(UIApplication.keyboardWillShowNotification) { isKeyboardVisible = true }
        .on(UIApplication.keyboardWillHideNotification) { isKeyboardVisible = false }
        .task { session.start() }
        .onAppear { fadeLiveIn() }
        .onChange(of: session.step) { previous, next in
            stepped(from: previous, to: next)
        }
        .onChange(of: session.lastError) { _, message in
            if message != nil { shakeField() }
        }
        .task(id: ghostToken) {
            guard ghost != nil else { return }
            // The copy is gone once its longest animation, the 0.4 s shrink, has finished.
            try? await Task.sleep(for: .seconds(0.4))
            ghost = nil
        }
        .task(id: isCodeFailed) {
            guard isCodeFailed else { return }
            try? await Task.sleep(for: .seconds(TelegramLoginMotion.failedResetDelay))
            isCodeFailed = false
            entry = ""
        }
    }

    @ViewBuilder private func screen(
        _ step: TdAuthorizationStep?,
        entry: Binding<String>,
        country: Binding<DialCountry>,
        screenWidth: CGFloat,
        motion: HandOver,
        isGhost: Bool
    ) -> some View {
        let subtitleText = subtitle(for: step)

        VStack(spacing: 0) {
            gap(TelegramLoginMetrics.topInset)

            VStack(spacing: 0) {
                Text(title(for: step))
                    .font(titleFont(for: step))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(list.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !subtitleText.isEmpty {
                    gap(TelegramLoginMetrics.titleToSubtitle)

                    Text(subtitleText)
                        .font(TelegramLoginTypography.subtitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(list.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .offset(y: motion.textOffset)
            .opacity(motion.alpha)

            fieldGap(for: step)

            VStack(spacing: 0) {
                field(
                    step,
                    entry: entry,
                    country: country,
                    screenWidth: screenWidth,
                    isGhost: isGhost
                )

                if !isGhost, let message = session.lastError {
                    Text(message)
                        .font(TelegramLoginTypography.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(list.destructive)
                        .padding(.top, TelegramLoginMotion.errorOffset(screenWidth: screenWidth))
                }

                if let resend = resendTitle(for: step) {
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
            }
            .modifier(
                LoginShake(
                    progress: isGhost ? 0 : shakeProgress,
                    offsets: isGhost ? [] : shakeOffsets
                )
            )
            .offset(y: motion.fieldOffset)
            .scaleEffect(motion.fieldScale)
            .opacity(motion.alpha)

            Spacer(minLength: 0)

            TelegramPrimaryButton(
                palette: list,
                title: buttonTitle(for: step),
                isBusy: session.isWaiting,
                isEnabled: canContinue(step, entry: entry.wrappedValue),
                action: { submit(step, entry: entry.wrappedValue) }
            )
            .opacity(isGhost ? 0 : 1)
        }
        .padding(.horizontal, TelegramLoginMetrics.horizontalInset)
        .padding(.bottom, TelegramLoginMetrics.buttonToBottom)
    }

    // MARK: - Choreography

    private func stepped(
        from previous: TdAuthorizationStep?,
        to next: TdAuthorizationStep?
    ) {
        guard screen(of: previous) != screen(of: next) else { return }

        let outgoing = Ghost(step: previous, entry: entry, country: country)
        withoutAnimation {
            entry = ""
            isCodeFailed = false
            shakeOffsets = []
            shakeProgress = 0
        }

        if screen(of: previous) != .busy {
            handOver(outgoing)
        } else {
            withoutAnimation { ghost = nil }
        }
        fadeLiveIn()
    }

    private func handOver(_ outgoing: Ghost) {
        withoutAnimation {
            ghost = outgoing
            ghostToken += 1
            ghostTextOffset = 0
            ghostFieldOffset = 0
            ghostFieldScale = 1
            ghostAlpha = 1
        }
        withAnimation(TelegramLoginMotion.spring) {
            ghostTextOffset = TelegramLoginMotion.ghostTextOffset
            ghostFieldOffset = TelegramLoginMotion.ghostFieldOffset
        }
        withAnimation(TelegramLoginMotion.ghostScale) {
            ghostFieldScale = TelegramLoginMotion.ghostFieldScale
        }
        withAnimation(TelegramLoginMotion.ghostFade) {
            ghostAlpha = 0
        }
    }

    private func fadeLiveIn() {
        withoutAnimation { liveAlpha = 0 }
        withAnimation(TelegramLoginMotion.fadeIn) { liveAlpha = 1 }
    }

    /// The boxes take the hard shake, the word and phrase fields the gentle one, and only the
    /// code screen reports a failure this way.
    private func shakeField() {
        guard screen(of: session.step) == .code, let current = codeDelivery(of: session.step) else { return }
        withoutAnimation { shakeProgress = 0 }
        if current.lengthOfCode != nil {
            withoutAnimation { shakeOffsets = TelegramLoginMotion.codeShake }
            isCodeFailed = true
            withAnimation(.linear(duration: TelegramLoginMotion.codeShakeDuration)) { shakeProgress = 1 }
        } else {
            withoutAnimation { shakeOffsets = TelegramLoginMotion.wordShake }
            withAnimation(.linear(duration: TelegramLoginMotion.wordShakeDuration)) { shakeProgress = 1 }
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    private func screen(of step: TdAuthorizationStep?) -> Screen {
        switch step {
        case .waitPhoneNumber?, nil:
            .phone
        case .waitCode?:
            .code
        case .waitPassword?:
            .password
        case .waitOtherDeviceConfirmation?:
            .otherDevice
        case .waitRegistration?:
            .signUp
        case .ready?:
            .ready
        case .loggingOut?, .closing?, .closed?, .waitTdlibParameters?:
            .busy
        case .unknown(let type)?:
            .other(type)
        }
    }

    private func codeDelivery(of step: TdAuthorizationStep?) -> TdAuthorizationStep.CodeDelivery? {
        guard case .waitCode(_, let current, _, _)? = step else { return nil }
        return current
    }

    // MARK: - Per-screen content

    /// Telegram keeps the title at 30 light until the keyboard takes the lower half of the
    /// screen, then swaps it for 28 bold instead of pushing it up.
    private func titleFont(for step: TdAuthorizationStep?) -> Font {
        if screen(of: step) == .phone {
            return isKeyboardVisible
                ? TelegramLoginTypography.phoneTitleActive
                : TelegramLoginTypography.phoneTitleIdle
        }
        return TelegramLoginTypography.title
    }

    private func title(for step: TdAuthorizationStep?) -> String {
        switch step {
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

    private func subtitle(for step: TdAuthorizationStep?) -> String {
        switch step {
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
    @ViewBuilder private func fieldGap(for step: TdAuthorizationStep?) -> some View {
        switch step {
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

    @ViewBuilder private func field(
        _ step: TdAuthorizationStep?,
        entry: Binding<String>,
        country: Binding<DialCountry>,
        screenWidth: CGFloat,
        isGhost: Bool
    ) -> some View {
        switch step {
        case .waitPhoneNumber?, nil:
            PhoneNumberField(
                palette: list,
                country: country,
                nationalNumber: entry,
                isGhost: isGhost
            )
        case .waitCode(_, let current, _, _):
            switch current.lengthOfCode {
            case let length?:
                CodeBoxes(
                    palette: list,
                    length: length,
                    isCompact: screenWidth <= 320 || (screenWidth <= 375 && length > 5),
                    entry: isCodeFailed ? .failed : .normal,
                    text: entry
                )
            case nil:
                UnderlineField(
                    palette: list,
                    placeholder: current.placeholder,
                    text: entry,
                    isGhost: isGhost
                )
            }
        case .waitPassword?:
            UnderlineField(
                palette: list,
                placeholder: "Mật khẩu",
                text: entry,
                isSecure: true,
                isGhost: isGhost
            )
        default:
            EmptyView()
        }
    }

    private func buttonTitle(for step: TdAuthorizationStep?) -> String {
        switch step {
        case .waitPassword?: "Đăng nhập"
        default: "Tiếp tục"
        }
    }

    private func resendTitle(for step: TdAuthorizationStep?) -> String? {
        guard case .waitCode(_, _, let next, _)? = step, next != nil else { return nil }
        return "Gửi lại mã"
    }

    private func canContinue(_ step: TdAuthorizationStep?, entry: String) -> Bool {
        switch screen(of: step) {
        case .phone:
            entry.contains { $0.isNumber }
        case .code, .password:
            !entry.isEmpty
        default:
            false
        }
    }

    private func submit(_ step: TdAuthorizationStep?, entry: String) {
        switch screen(of: step) {
        case .phone:
            session.submitPhoneNumber(country.dialCode + String(entry.filter { $0.isNumber }))
        case .code:
            session.submitCode(entry)
        case .password:
            session.submitPassword(entry)
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
