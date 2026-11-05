import Foundation

public enum LyricsCacheCodec {
    private struct QQRecord: Codable {
        let payload: QQLyricPayload
        let duetReferenceLRC: String?
    }

    public static func encode(_ payload: LyricsPayload) -> String {
        switch payload {
        case .amll(let text):
            return "T" + text
        case .netEase(let record):
            return "E" + (json(record) ?? "{}")
        case .qq(let record, let duetReferenceLRC):
            return "Q" + (json(QQRecord(payload: record,
                                        duetReferenceLRC: duetReferenceLRC)) ?? "{}")
        case .lrclib(.synced(let text)):
            return "S" + text
        case .lrclib(.plain(let text)):
            return "P" + text
        case .lrclib(.none):
            return "N"
        case .pureMusic:
            return "U"
        }
    }

    public static func decode(_ stored: String) -> LyricsPayload? {
        guard let marker = stored.first else { return nil }
        let body = String(stored.dropFirst())
        switch marker {
        case "T":
            return LyricsPayload.amll(body)
        case "E":
            guard let data = body.data(using: .utf8),
                  let record = try? JSONDecoder().decode(NetEaseLyricPayload.self, from: data)
            else { return nil }
            return .netEase(record)
        case "Q":
            guard let data = body.data(using: .utf8),
                  let record = try? JSONDecoder().decode(QQRecord.self, from: data)
            else { return nil }
            return .qq(record.payload, duetReferenceLRC: record.duetReferenceLRC)
        case "S":
            return .lrclib(.synced(body))
        case "P":
            return .lrclib(.plain(body))
        case "N":
            return .lrclib(.none)
        case "U":
            return .pureMusic
        default:
            return nil
        }
    }

    private static func json(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
