import Foundation
import Testing
@testable import TdSession

/// Each case is the JSON TDLib actually sends, copied from the pinned schema.
@Test(arguments: [
    ("authorizationStateWaitTdlibParameters", TdAuthorizationStep.waitTdlibParameters),
    ("authorizationStateWaitPhoneNumber", TdAuthorizationStep.waitPhoneNumber),
    ("authorizationStateReady", TdAuthorizationStep.ready),
    ("authorizationStateLoggingOut", TdAuthorizationStep.loggingOut),
    ("authorizationStateClosing", TdAuthorizationStep.closing),
    ("authorizationStateClosed", TdAuthorizationStep.closed),
])
func decodesPlainStates(type: String, expected: TdAuthorizationStep) {
    let state = TdJSON.parse(#"{"@type":"\#(type)"}"#) ?? .null
    #expect(TdAuthorizationStep.decode(state) == expected)
}

@Test("A code request says where the code went and how long it is")
func decodesCodeState() {
    let state = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitCode",
         "code_info":{"phone_number":"+84905000000","timeout":60,
                      "type":{"@type":"authenticationCodeTypeSms","length":6},
                      "next_type":{"@type":"authenticationCodeTypeCall","length":0}}}
        """
    ) ?? .null
    #expect(
        TdAuthorizationStep.decode(state)
            == .waitCode(
                phoneNumber: "+84905000000",
                current: .sms(length: 6),
                next: .call(length: 0),
                timeout: 60
            )
    )
}

@Test("The password hint is shown, the recovery address is only a pattern")
func decodesPasswordState() {
    let state = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitPassword",
         "password_hint":"doni","has_recovery_email_address":true,
         "recovery_email_address_pattern":"k***@example.com"}
        """
    ) ?? .null
    #expect(
        TdAuthorizationStep.decode(state)
            == .waitPassword(
                hint: "doni",
                hasRecoveryEmailAddress: true,
                emailAddressPattern: "k***@example.com"
            )
    )
}

@Test("Login by QR needs the link the other device scans")
func decodesOtherDeviceState() {
    let state = TdJSON.parse(
        #"{"@type":"authorizationStateWaitOtherDeviceConfirmation","link":"tg://login?token=abc"}"#
    ) ?? .null
    #expect(TdAuthorizationStep.decode(state) == .waitOtherDeviceConfirmation(link: "tg://login?token=abc"))
}

@Test("An unregistered number needs the terms accepted before a name is asked for")
func decodesRegistrationState() {
    let state = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitRegistration",
         "terms_of_service":{"text":{"text":"..."},"min_user_age":18,"show_popup":true}}
        """
    ) ?? .null
    #expect(TdAuthorizationStep.decode(state) == .waitRegistration(minimumAge: 18))
}

@Test("A word or a phrase replaces the digits for SMS delivery")
func decodesSmsWordAndPhraseDeliveries() {
    let word = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitCode",
         "code_info":{"phone_number":"+84905000000","timeout":0,
                      "type":{"@type":"authenticationCodeTypeSmsWord","first_letter":"b"}}}
        """
    ) ?? .null
    #expect(
        TdAuthorizationStep.decode(word)
            == .waitCode(phoneNumber: "+84905000000", current: .smsWord(firstLetter: "b"), next: nil, timeout: 0)
    )

    let phrase = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitCode",
         "code_info":{"phone_number":"+84905000000","timeout":0,
                      "type":{"@type":"authenticationCodeTypeSmsPhrase","first_word":"bank"}}}
        """
    ) ?? .null
    #expect(
        TdAuthorizationStep.decode(phrase)
            == .waitCode(
                phoneNumber: "+84905000000",
                current: .smsPhrase(firstWord: "bank"),
                next: nil,
                timeout: 0
            )
    )
}

@Test("A missed call delivery says which prefix to dial and how many digits")
func decodesMissedCallDelivery() {
    let state = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitCode",
         "code_info":{"phone_number":"+84905000000","timeout":0,
                      "type":{"@type":"authenticationCodeTypeMissedCall",
                              "phone_number_prefix":"3","length":5}}}
        """
    ) ?? .null
    #expect(
        TdAuthorizationStep.decode(state)
            == .waitCode(
                phoneNumber: "+84905000000",
                current: .missedCall(prefix: "3", length: 5),
                next: nil,
                timeout: 0
            )
    )
}

@Test("A flash call hands the user a pattern to key in")
func decodesFlashCallDelivery() {
    let state = TdJSON.parse(
        """
        {"@type":"authorizationStateWaitCode",
         "code_info":{"phone_number":"+84905000000","timeout":0,
                      "type":{"@type":"authenticationCodeTypeFlashCall","pattern":"ab*"}}}
        """
    ) ?? .null
    #expect(
        TdAuthorizationStep.decode(state)
            == .waitCode(
                phoneNumber: "+84905000000",
                current: .flashCall(pattern: "ab*"),
                next: nil,
                timeout: 0
            )
    )
}

@Test("A state from a newer TDLib is named, not swallowed")
func unknownStateKeepsItsType() {
    let state = TdJSON.parse(#"{"@type":"authorizationStateWaitSomethingNew"}"#) ?? .null
    #expect(TdAuthorizationStep.decode(state) == .unknown(type: "authorizationStateWaitSomethingNew"))
}

@Test("A payload without @type cannot be mistaken for a state")
func missingTypeIsUnknown() {
    #expect(TdAuthorizationStep.decode(.null) == .unknown(type: "missing @type"))
}

@Test("A code state missing its info still reports the phone it is waiting for")
func codeStateWithoutInfo() {
    let state = TdJSON.parse(#"{"@type":"authorizationStateWaitCode"}"#) ?? .null
    #expect(
        TdAuthorizationStep.decode(state)
            == .waitCode(phoneNumber: "", current: .unknown(type: "missing"), next: nil, timeout: 0)
    )
}
