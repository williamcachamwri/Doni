import SwiftUI
import TelegramDesignSystem
import TdSession

/// Login: one screen per authorization state, driven by TDLib's state rather than by a step
/// counter, so a session that resumes at the code step or at the password step shows the right
/// field without extra bookkeeping.
///
/// The layout follows `Docs/design-tokens.md`, "Login (authorization sequence)": measured type,
/// ruled fields, a capsule button 24 pt above the keyboard, content hanging from the top with its
/// gaps stretching to their maxima, which is how `layoutAuthorizationItems` distributes the space a
/// screen leaves over. What it does not follow is the reference's white canvas: this is the front
/// door of a dark music app, so it wears the shell's black, the shell's accent and a backdrop that
/// moves, and the mark sits in the slot the reference keeps for its 100×100 intro sticker.
///
/// The hand-over between two screens is Telegram's snapshot choreography: the outgoing screen is
/// kept on stage as a frozen copy, thrown 100–140 pt up while the field block shrinks to 30 % and
/// both fade out, and the incoming screen fades up over it — growing its own mark from 30 % the way
/// the incoming sticker does. The button is the one element that belongs to no screen, so it is
/// hidden in the copy and never fades.
struct LoginView: View {
    @ObservedObject var session: TelegramSession

    @State private var country = DialCountry.current()
    /// The one field on stage: the national number, the code, or the password.
    @State private var entry = ""
    @State private var isKeyboardVisible = false

    /// Backing out of a code screen is a UI move, not a protocol one: TDLib keeps waiting for the
    /// code it sent, and takes a new phone number from that state (`TdLoginFlow.submitPhoneNumber`).
    @State private var isPickingANewNumber = false
    @State private var savedNumber = ""
    @State private var savedCountry = DialCountry.current()
    @State private var isAskingToStop = false

    @State private var ghost: Ghost?
    @State private var ghostToken = 0
    @State private var ghostTextOffset: CGFloat = 0
    @State private var ghostFieldOffset: CGFloat = 0
    @State private var ghostFieldScale: CGFloat = 1
    @State private var ghostAlpha: Double = 1
    @State private var liveAlpha = 0.0
    /// The incoming screen's mark grows from 30 % in the same 0.3 s its nodes fade up, which is the
    /// reference's own rule for the sticker that stands in this slot.
    @State private var liveCrestScale = 1.0

    @State private var shakeOffsets: [CGFloat] = []
    @State private var shakeProgress = 0.0
    @State private var isCodeFailed = false

    private let list = TelegramListPalette.night

    /// The screen that just left the stage, with everything it was showing.
    private struct Ghost {
        let step: TdAuthorizationStep?
        let entry: String
        let country: DialCountry
        /// The mark's size at the moment the copy was taken. A ghost is a frozen screen, so it keeps
        /// the side it was drawn at rather than tucking with a keyboard that has since come up.
        let crestSide: CGFloat
    }

    /// Where the frozen copy is in its flight.
    private struct HandOver {
        var textOffset: CGFloat = 0
        var fieldOffset: CGFloat = 0
        var fieldScale: CGFloat = 1
        var alpha: Double = 1
        var crestSide: CGFloat = TelegramLoginMetrics.crestSide
        var crestScale: CGFloat = 1
    }

    /// Two updates of the same screen must not replay the hand-over — TDLib resends the code
    /// state when a code is reissued, and Telegram does not animate for that.
    private enum Screen: Equatable {
        case phone, code, password, otherDevice, signUp, ready, busy, other(String)
    }

    var body: some View {
        ZStack {
            LoginBackdrop(canvas: list.background)

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
                                alpha: ghostAlpha,
                                crestSide: ghost.crestSide
                            ),
                            isGhost: true
                        )
                        .allowsHitTesting(false)
                    }

                    screen(
                        isPickingANewNumber ? .waitPhoneNumber : session.step,
                        entry: $entry,
                        country: $country,
                        screenWidth: proxy.size.width,
                        motion: HandOver(alpha: liveAlpha,
                                         crestSide: liveCrestSide,
                                         crestScale: liveCrestScale),
                        isGhost: false
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                if offersBack(session.step), !isPickingANewNumber {
                    backButton
                }
            }
        }
        // The sequence is a screen of the app, so it forces the appearance the rest of the app is
        // rendered in — including the keyboard, which would otherwise come up white over black.
        .preferredColorScheme(.dark)
        .on(UIApplication.keyboardWillShowNotification) {
            withAnimation(TelegramLoginMotion.presentation) { isKeyboardVisible = true }
        }
        .on(UIApplication.keyboardWillHideNotification) {
            withAnimation(TelegramLoginMotion.presentation) { isKeyboardVisible = false }
        }
        .task { session.start() }
        .onAppear { fadeLiveIn() }
        .alert(
            Text(verbatim: ""),
            isPresented: $isAskingToStop,
            actions: {
                Button("Tiếp tục", role: .cancel) {}
                Button("Dừng") { stopAndGoBack() }
            },
            message: { Text("Bạn muốn dừng quá trình nhập mã và quay lại chọn số điện thoại khác?") }
        )
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

    /// Telegram's navigation bar over the authorization sequence is transparent — clear background,
    /// clear separator (`AuthorizationSequenceController.swift:84`) — so all of it that reaches the
    /// screen is this chevron, tinted with the bar's own accent (`NavigationBackButtonNode.swift:34`).
    private var backButton: some View {
        Button(action: { isAskingToStop = true }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(list.accent)
                .frame(width: TelegramLoginMetrics.backButtonSide,
                       height: TelegramLoginMetrics.navigationBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(liveAlpha)
    }

    /// Every screen after the phone number can be backed out of, because TDLib takes a new number
    /// from all of them.
    private func offersBack(_ step: TdAuthorizationStep?) -> Bool {
        switch screen(of: step) {
        case .code, .password, .otherDevice, .signUp:
            true
        default:
            false
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
        /// The screens that offer the back chevron hang below the navigation bar it lives in;
        /// the phone screen owns the whole band, as it does in the reference.
        let navBand = offersBack(step) ? TelegramLoginMetrics.navigationBarHeight : 0

        VStack(spacing: 0) {
            gap(TelegramLoginMetrics.topInset + navBand)

            VStack(spacing: 0) {
                // The mark travels with the title block, so a hand-over throws both of them up and
                // the incoming one grows back from 30 % — the sticker's own rule in the reference.
                LoginCrest(side: motion.crestSide)
                    .scaleEffect(motion.crestScale)
                    .padding(.bottom, TelegramLoginMetrics.crestToTitle)

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
        // The block has to be told to take the width it is offered. A VStack sizes itself to its
        // widest child's ideal width, and a subtitle like "Chúng tôi đã gửi mã 5 chữ số cho
        // +84562106190." asks for more than the screen, so the block grew past the canvas and the
        // ZStack centred it — which pulled every other row, including the country name and the
        // dial code, off the left edge. Clamped here, the text wraps and the absolute insets below
        // (`dialCodeLeading`, `countryLeading`) land where they are measured to land.
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TelegramLoginMetrics.horizontalInset)
        .padding(.bottom, TelegramLoginMetrics.buttonToBottom)
    }

    // MARK: - Choreography

    private func stepped(
        from previous: TdAuthorizationStep?,
        to next: TdAuthorizationStep?
    ) {
        guard screen(of: previous) != screen(of: next) else { return }

        if screen(of: previous) == .phone {
            savedNumber = entry
            savedCountry = country
        }

        let outgoing = Ghost(step: previous, entry: entry, country: country,
                             crestSide: liveCrestSide)
        withoutAnimation {
            entry = ""
            isCodeFailed = false
            shakeOffsets = []
            shakeProgress = 0
            isPickingANewNumber = false
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
        withoutAnimation {
            liveAlpha = 0
            liveCrestScale = TelegramLoginMotion.crestFrom
        }
        withAnimation(TelegramLoginMotion.fadeIn) {
            liveAlpha = 1
            liveCrestScale = 1
        }
    }

    /// The mark keeps the sticker's slot and gives up height when the keyboard takes the lower half
    /// of the screen — the same trade the phone screen makes by swapping 30 pt light type for 28 pt
    /// bold, made here without moving anything the eye is following.
    private var liveCrestSide: CGFloat {
        isKeyboardVisible ? TelegramLoginMetrics.crestTuckedSide : TelegramLoginMetrics.crestSide
    }

    /// The code screen flies up exactly as it did on the way forward — nothing is sent anywhere,
    /// the number screen is simply put back on stage with the number it was left with.
    private func stopAndGoBack() {
        let outgoing = Ghost(step: session.step, entry: entry, country: country,
                             crestSide: liveCrestSide)
        withoutAnimation {
            isPickingANewNumber = true
            entry = savedNumber
            country = savedCountry
            isCodeFailed = false
            shakeOffsets = []
            shakeProgress = 0
        }
        handOver(outgoing)
        fadeLiveIn()
    }

    /// The other half: TDLib does not re-announce the code state for a number it was already
    /// waiting on, so the way back to it is driven from here rather than from `stepped`.
    private func returnToCode() {
        savedNumber = entry
        savedCountry = country
        let outgoing = Ghost(step: .waitPhoneNumber, entry: entry, country: country,
                             crestSide: liveCrestSide)
        withoutAnimation {
            isPickingANewNumber = false
            entry = ""
        }
        handOver(outgoing)
        fadeLiveIn()
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
            let number = country.dialCode + String(entry.filter { $0.isNumber })
            if isPickingANewNumber {
                session.submitPhoneNumber(number, then: returnToCode)
            } else {
                session.submitPhoneNumber(number)
            }
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

/// The app's mark, standing in the slot the reference keeps for its 100×100 intro sticker. Doni
/// ships no Lottie and no asset catalog, so this is drawn from the same accent tile the settings
/// header wears — which is also the one thing on this screen that says whose app the login opens.
private struct LoginCrest: View {
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * TelegramLoginMetrics.crestRadiusRatio,
                         style: .continuous)
            .fill(MusicTint.accent)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// The canvas the sequence is read on: the shell's black, and two soft colours drifting slowly
/// behind the words.
///
/// They move because nothing here sits under the content as a panel — a light that never travels is
/// a background card, and the fields already have their own rules to stand on. Two radial gradients
/// rather than blurred discs for the same reason: they are soft by construction, so an eleven-second
/// drift costs a fill instead of a Gaussian pass every frame.
private struct LoginBackdrop: View {
    let canvas: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            canvas

            glow(MusicTint.accent, opacity: 0.34, side: 460)
                .offset(x: drift ? -86 : 74, y: drift ? -168 : -104)

            glow(Color(rgb: 0x3e88f7), opacity: 0.20, side: 520)
                .offset(x: drift ? 92 : -70, y: drift ? 176 : 108)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, opacity: Double, side: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(opacity), color.opacity(0)],
                       center: .center, startRadius: 0, endRadius: side / 2)
            .frame(width: side, height: side)
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
