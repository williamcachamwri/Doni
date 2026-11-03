import Foundation

/// What the user has to do next, as the login screen needs it.
///
/// Mirrors `AuthorizationState` in the pinned TDLib schema (`td_api.tl:206-263`)
/// and keeps the data each state carries, because the UI shows it: the code
/// length, the password hint, the confirmation link. `unknown` exists so a
/// state TDLib adds later degrades to a message instead of a crash.
public enum TdAuthorizationStep: Equatable, Sendable {
    case waitTdlibParameters
    case waitPhoneNumber
    case waitCode(phoneNumber: String, current: CodeDelivery, next: CodeDelivery?, timeout: Int)
    case waitOtherDeviceConfirmation(link: String)
    case waitRegistration(minimumAge: Int)
    case waitPassword(hint: String, hasRecoveryEmailAddress: Bool, emailAddressPattern: String)
    case ready
    case loggingOut
    case closing
    case closed
    case unknown(type: String)

    public enum CodeDelivery: Equatable, Sendable {
        case telegramMessage(length: Int)
        case sms(length: Int)
        /// SMS-based authentication with a word that starts with the given
        /// letter (`td_api.tl:37`) — the user types the word, not digits.
        case smsWord(firstLetter: String)
        case smsPhrase(firstWord: String)
        case call(length: Int)
        case flashCall(pattern: String)
        case missedCall(prefix: String, length: Int)
        case unknown(type: String)
    }

    /// `state` is an `authorizationState*` object — either the payload of
    /// `updateAuthorizationState` or the answer to `getAuthorizationState`.
    public static func decode(_ state: TdJSON) -> TdAuthorizationStep {
        guard let type = state.type else { return .unknown(type: "missing @type") }
        switch type {
        case "authorizationStateWaitTdlibParameters":
            return .waitTdlibParameters
        case "authorizationStateWaitPhoneNumber":
            return .waitPhoneNumber
        case "authorizationStateWaitCode":
            return decodeCode(state["code_info"] ?? .null)
        case "authorizationStateWaitOtherDeviceConfirmation":
            return .waitOtherDeviceConfirmation(link: state["link"]?.string ?? "")
        case "authorizationStateWaitRegistration":
            return .waitRegistration(
                minimumAge: Int(state["terms_of_service"]?["min_user_age"]?.int ?? 13)
            )
        case "authorizationStateWaitPassword":
            return .waitPassword(
                hint: state["password_hint"]?.string ?? "",
                hasRecoveryEmailAddress: state["has_recovery_email_address"]?.bool ?? false,
                emailAddressPattern: state["recovery_email_address_pattern"]?.string ?? ""
            )
        case "authorizationStateReady":
            return .ready
        case "authorizationStateLoggingOut":
            return .loggingOut
        case "authorizationStateClosing":
            return .closing
        case "authorizationStateClosed":
            return .closed
        default:
            return .unknown(type: type)
        }
    }

    private static func decodeCode(_ info: TdJSON) -> TdAuthorizationStep {
        .waitCode(
            phoneNumber: info["phone_number"]?.string ?? "",
            current: codeDelivery(info["type"] ?? .null),
            next: info["next_type"].map(codeDelivery),
            timeout: Int(info["timeout"]?.int ?? 0)
        )
    }

    private static func codeDelivery(_ value: TdJSON) -> CodeDelivery {
        switch value.type ?? "missing" {
        case "authenticationCodeTypeTelegramMessage":
            .telegramMessage(length: Int(value["length"]?.int ?? 5))
        case "authenticationCodeTypeSms":
            .sms(length: Int(value["length"]?.int ?? 5))
        case "authenticationCodeTypeSmsWord":
            .smsWord(firstLetter: value["first_letter"]?.string ?? "")
        case "authenticationCodeTypeSmsPhrase":
            .smsPhrase(firstWord: value["first_word"]?.string ?? "")
        case "authenticationCodeTypeCall":
            .call(length: Int(value["length"]?.int ?? 5))
        case "authenticationCodeTypeFlashCall":
            .flashCall(pattern: value["pattern"]?.string ?? "")
        case "authenticationCodeTypeMissedCall":
            .missedCall(
                prefix: value["phone_number_prefix"]?.string ?? "",
                length: Int(value["length"]?.int ?? 5)
            )
        case let type:
            .unknown(type: type)
        }
    }
}
