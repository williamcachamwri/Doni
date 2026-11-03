import SwiftUI
import TelegramDesignSystem
import TdSession

/// Login: one screen per authorization state, driven by TDLib's state rather
/// than by a step counter, so a session that resumes at the code step or at the
/// password step shows the right field without extra bookkeeping.
///
/// The layout is plain on purpose: the login metrics are not in
/// Docs/design-tokens.md yet, and this screen is matched pixel-by-pixel in M4
/// like the others. Only colours with a known source are used.
struct LoginView: View {
    @ObservedObject var session: TelegramSession
    @State private var phoneNumber = "+84"
    @State private var code = ""
    @State private var password = ""

    private let palette = TelegramPalette.day

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            field
            if let message = session.lastError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(palette.chatListDraftText)
            }
            continueButton
            if case .waitCode(_, _, let next, _)? = session.step, next != nil {
                Button("Gửi lại mã") { session.resendCode() }
                    .font(.footnote)
                    .disabled(session.isWaiting)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.chatListBackground)
        .task { session.start() }
    }

    @ViewBuilder private var header: some View {
        switch session.step {
        case .waitPhoneNumber?, nil:
            title("Số điện thoại", "Nhập số điện thoại của bạn để tiếp tục.")
        case .waitCode(let sentTo, let current, _, _):
            title("Mã xác minh", codeNote(sentTo: sentTo, delivery: current))
        case .waitPassword(let hint, _, _):
            title("Mật khẩu hai bước", hint.isEmpty ? "Nhập mật khẩu bạn đã đặt." : "Gợi ý: \(hint)")
        case .ready?:
            EmptyView()
        case .unknown(let type)?:
            title("Trạng thái không hỗ trợ", type)
        case .waitRegistration(let termsId, _)?:
            title("Cần đăng ký tài khoản", "Số này chưa có tài khoản Telegram (terms \(termsId)).")
        case .waitOtherDeviceConfirmation(let link)?:
            title("Xác nhận trên thiết bị khác", link)
        default:
            Text("Đang chuẩn bị…")
                .font(.title2.bold())
                .foregroundStyle(palette.chatListTitle)
        }
    }

    private func title(_ heading: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(.largeTitle.bold())
                .foregroundStyle(palette.chatListTitle)
            Text(detail)
                .font(.callout)
                .foregroundStyle(palette.chatListMessageText)
        }
    }

    @ViewBuilder private var field: some View {
        switch session.step {
        case .waitPhoneNumber?, nil:
            TextField("+84 905 000 000", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .textFieldStyle(.roundedBorder)
        case .waitCode?:
            TextField("Mã", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.roundedBorder)
        case .waitPassword?:
            SecureField("Mật khẩu", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
        default:
            EmptyView()
        }
    }

    private var continueButton: some View {
        Button {
            switch session.step {
            case .waitPhoneNumber?, nil: session.submitPhoneNumber(phoneNumber)
            case .waitCode?: session.submitCode(code)
            case .waitPassword?: session.submitPassword(password)
            default: break
            }
        } label: {
            Text("Tiếp tục")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accent)
        .disabled(session.isWaiting || !canContinue)
    }

    private var canContinue: Bool {
        switch session.step {
        case .waitPhoneNumber?, nil: !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
        case .waitCode?: !code.isEmpty
        case .waitPassword?: !password.isEmpty
        default: false
        }
    }

    /// Only the number of digits is interpolated; anything TDLib says about
    /// how the code is delivered is left to the resend button.
    private func codeNote(sentTo: String, delivery: TdAuthorizationStep.CodeDelivery) -> String {
        let digits: String
        switch delivery {
        case .telegramMessage(let length), .sms(let length), .call(let length), .missedCall(_, let length):
            digits = "\(length)"
        case .flashCall, .unknown:
            digits = ""
        }
        return digits.isEmpty
            ? "Chúng tôi đã gửi mã cho \(sentTo)."
            : "Chúng tôi đã gửi mã \(digits) ký tự cho \(sentTo)."
    }
}
