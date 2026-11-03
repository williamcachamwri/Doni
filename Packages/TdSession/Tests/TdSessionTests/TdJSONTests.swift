import Foundation
import Testing
@testable import TdSession

@Test("Message ids survive a parse without losing precision")
func largeIdsStayExact() {
    let json = TdJSON.parse(#"{"id":1234567890123456789,"small":42,"ratio":1.5,"on":true,"off":false}"#)
    #expect(json?["id"]?.int == 1234567890123456789)
    #expect(json?["small"]?.int == 42)
    #expect(json?["ratio"]?.double == 1.5)
    // JSON has no integer 1 that could be confused with true: objCType "c" is
    // only ever a boolean.
    #expect(json?["on"]?.bool == true)
    #expect(json?["off"]?.bool == false)
    #expect(json?["off"]?.int == nil)
}

@Test("Serializing then parsing gives the same tree back")
func roundTrip() {
    let original: TdJSON = .object([
        "@type": .string("tdlibParameters"),
        "api_id": .int(1234),
        "use_message_database": .bool(true),
        "device_model": .string("iPhone 16e"),
        "empty": .null,
        "list": .array([.int(1), .double(2.5), .string("x")]),
        "nested": .object(["@type": .string("searchFilterMessages")]),
    ])
    let text = original.serialized
    #expect(text != nil)
    #expect(TdJSON.parse(text ?? "") == original)
}

@Test("Anything that is not JSON is rejected rather than guessed at")
func rejectsGarbage() {
    #expect(TdJSON.parse("{ not json") == nil)
    #expect(TdJSON.parse("") == nil)
    #expect(TdJSON.parse(#"{"a":}"#) == nil)
}

@Test("Subscripts only reach into the container they are given")
func subscriptGuardsShape() {
    let object = TdJSON.parse(#"{"a":{"b":1},"list":[7]}"#)
    #expect(object?["a"]?["b"]?.int == 1)
    #expect(object?["missing"] == nil)
    #expect(object?["a"]?[0] == nil)
    #expect(object?["list"]?[0]?.int == 7)
    #expect(object?["list"]?[1] == nil)
    #expect(TdJSON.int(5)["a"] == nil)
}
