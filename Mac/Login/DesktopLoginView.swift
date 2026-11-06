import SwiftUI
import TdSession
import TelegramDesignSystem

/// Signing in on a Mac window.
///
/// The reference's desktop logs in with a NetEase cookie, which is no use here, so this is Doni's own
/// authorization sequence — the same `TelegramSession` steps the phone drives — laid out for a window
/// rather than the phone's 520 pt canvas. The wording is deliberately the phone's wording: the catalog
/// already carries every one of these sentences in six languages, and two spellings of the same Telegram
/// prompt is how an app starts to disagree with itself.
///
/// Every sentence here is handed to `Text` as a literal at its own branch. A computed `String` read by
/// `Text(_:)` takes the verbatim initializer, and a ternary of two literals infers `String` too — the
/// trap that shipped Vietnamese to five languages on the phone, which the strings gate cannot see because
/// the row it checks does exist.
struct DesktopLoginView: View {
    @ObservedObject var session: TelegramSession
    @FocusState private var field: Field?

    private enum Field { case phone, code, password }

    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 18) {
            mark
            title
                .font(.system(size: 28, weight: .bold))
            subtitle
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            editor
                .frame(width: 320)
                .padding(.top, 12)

            // Enter submits from the field, but a window needs something to press: a form whose only
            // door is the keyboard reads as a broken dialog on the desktop.
            Button(action: submit) {
                Text("Tiếp tục")
                    .frame(maxWidth: 320)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(MusicTint.accent)
            .disabled(session.isWaiting || entryIsEmpty)

            // A sentence the session assembled from a TDLib failure, already looked up: not a key.
            if let message = session.lastError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if resendIsShown {
                Button { session.resendCode() } label: { Text("Gửi lại mã") }
                    .buttonStyle(.plain)
                    .foregroundStyle(session.isWaiting ? Color.secondary : MusicTint.accent)
                    .disabled(session.isWaiting)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { field = .phone }
    }

    /// The app's own mark, at the phone's proportion: the iOS icon mask is 22.5 % of the side, so the
    /// tile here and the icon on the springboard are one shape rather than two.
    private var mark: some View {
        Image("DoniMark")
            .resizable()
            .interpolation(.high)
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 96 * 0.225, style: .continuous))
            .accessibilityLabel("Doni")
    }

    @ViewBuilder private var editor: some View {
        switch session.step {
        case .waitCode:
            TextField("", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($field, equals: .code)
                .onSubmit(submit)
        case .waitPassword:
            SecureField("", text: $password)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .focused($field, equals: .password)
                .onSubmit(submit)
        default:
            TextField("+84 90 123 4567", text: $phone)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .focused($field, equals: .phone)
                .onSubmit(submit)
        }
    }

    /// Each branch hands `Text` a resolved sentence rather than a `String` built by interpolation:
    /// `Text("Nhập mã \(length) chữ số")` *is* a localization key to Swift, but the key it builds
    /// depends on the argument's type, so no row in the table can name it and every language falls back
    /// to Vietnamese. `localized(_:_:)` is the form that can be answered.
    @ViewBuilder private var title: some View {
        switch session.step {
        case .waitPhoneNumber?, nil: Text("Số điện thoại của bạn")
        case .waitCode(_, let current, _, _):
            switch current.lengthOfCode {
            case let length?: Text(localized("Nhập mã %@ chữ số", length.formatted()))
            case nil: Text("Nhập mã xác nhận")
            }
        case .waitPassword?: Text("Xác thực hai bước")
        case .waitOtherDeviceConfirmation?: Text("Xác nhận trên thiết bị khác")
        case .waitRegistration?: Text("Cần đăng ký tài khoản")
        case .loggingOut?, .closing?, .closed?: Text("Đang đăng xuất…")
        case .waitTdlibParameters?: Text("Đang chuẩn bị…")
        case .ready?: EmptyView()
        case .unknown(let type)?: Text(verbatim: type)
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch session.step {
        case .waitPhoneNumber?, nil: Text("Nhập số điện thoại của bạn để tiếp tục.")
        case .waitCode(_, let current, _, _): deliveryLine(current)
        case .waitPassword(let hint, _, _):
            if hint.isEmpty {
                Text("Nhập mật khẩu bạn đã đặt cho tài khoản này.")
            } else {
                Text(localized("Gợi ý: %@", hint))
            }
        case .waitRegistration(let minimumAge)?:
            Text(localized("Số này chưa có tài khoản Telegram và cần đủ %@ tuổi.",
                           minimumAge.formatted()))
        case .waitOtherDeviceConfirmation(let link)?: Text(verbatim: link)
        case .ready?, .loggingOut?, .closing?, .closed?, .waitTdlibParameters?, .unknown?: EmptyView()
        }
    }

    /// What Telegram actually sent decides what the user is asked to type: a digit code, an SMS word, or
    /// a phrase — the phone spells all three, and the desktop must not guess.
    @ViewBuilder private func deliveryLine(_ current: TdAuthorizationStep.CodeDelivery) -> some View {
        switch current {
        case .smsWord(let letter):
            Text(localized("Nhập từ bắt đầu bằng “%@” mà chúng tôi đã gửi.", letter))
        case .smsPhrase(let word):
            Text(localized("Nhập câu bắt đầu bằng “%@” mà chúng tôi đã gửi.", word))
        case .telegramMessage(let length), .sms(let length), .call(let length):
            Text(localized("Chúng tôi đã gửi mã %@ chữ số.", length.formatted()))
        case .flashCall(let pattern):
            Text(localized("Chúng tôi sẽ gọi và đọc mã theo dạng %@.", pattern))
        case .missedCall(let prefix, let length):
            Text(localized("Cuộc gọi nhỡ %@ và %@ số cuối.",
                           prefix, length.formatted()))
        case .unknown(let type): Text(verbatim: type)
        }
    }

    private var resendIsShown: Bool {
        if case .waitCode? = session.step { return true }
        return false
    }

    private var entryIsEmpty: Bool {
        switch session.step {
        case .waitCode?: code.isEmpty
        case .waitPassword?: password.isEmpty
        default: phone.isEmpty
        }
    }

    private func submit() {
        switch session.step {
        case .waitCode?: session.submitCode(code)
        case .waitPassword?: session.submitPassword(password)
        default: session.submitPhoneNumber(phone)
        }
    }
}
