import Foundation

/// A JSON tree that is `Sendable`, which `[String: Any]` from `JSONSerialization` is not: every TDLib
/// payload crosses a thread boundary, so the type carrying it has to be sendable by construction rather
/// than by assertion. Integers stay `Int64` — Telegram ids exceed 32 bits and lose precision in `Double`.
public enum TdJSON: Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([TdJSON])
    case object([String: TdJSON])
    case null

    public static func parse(_ text: String) -> TdJSON? {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return from(raw)
    }

    public var serialized: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: foundationValue),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    /// `@type`, the discriminator TDLib puts on every object.
    public var type: String? { self["@type"]?.string }

    public var string: String? { if case .string(let v) = self { v } else { nil } }
    /// The integer this is meant to be. JSON has no integer type, and a Telegram id written as `1.0`
    /// or `"123"` is still the same id; reading only the case the parser chose turns a real number into
    /// "no id", and the app then says something untrue about the account.
    public var int: Int64? {
        switch self {
        case .int(let value): value
        case .double(let value) where value == value.rounded() && abs(value) < 9.2e18: Int64(value)
        case .string(let value): Int64(value)
        default: nil
        }
    }
    public var double: Double? { if case .double(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var array: [TdJSON]? { if case .array(let v) = self { v } else { nil } }
    public var object: [String: TdJSON]? { if case .object(let v) = self { v } else { nil } }

    public subscript(key: String) -> TdJSON? {
        if case .object(let fields) = self { fields[key] } else { nil }
    }

    public subscript(index: Int) -> TdJSON? {
        guard case .array(let items) = self, items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// TDLib numbers arrive as `q`/`d` and booleans as `c`, so `objCType` is the
    /// only way to tell a JSON `true` from a JSON `1`.
    private static func from(_ raw: Any) -> TdJSON {
        switch raw {
        case let value as NSNumber:
            let encoding = String(cString: value.objCType)
            if encoding == "c" { return .bool(value.boolValue) }
            if encoding == "d" || encoding == "f" { return .double(value.doubleValue) }
            return .int(value.int64Value)
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(value.map(from))
        case let value as [String: Any]:
            return .object(value.mapValues(from))
        default:
            return .null
        }
    }

    private var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .array(let values): values.map(\.foundationValue)
        case .object(let fields): fields.mapValues(\.foundationValue)
        case .null: NSNull()
        }
    }
}
