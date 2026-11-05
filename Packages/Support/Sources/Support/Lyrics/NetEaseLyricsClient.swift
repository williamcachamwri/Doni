import CommonCrypto
import CryptoKit
import Foundation

struct NetEaseLyricsClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lyrics(for metadata: LyricSongMetadata) async throws
    -> (payload: NetEaseLyricPayload, amllTTML: String?) {
        guard let candidate = try await candidate(for: metadata) else {
            throw LyricSourceError.noLyrics
        }
        let candidateMetadata = LyricSongMetadata(
            title: candidate.name, artist: candidate.artist,
            album: candidate.album, durationSeconds: candidate.durationSeconds
        )
        async let payload = lyric(id: candidate.id)
        async let ttml = AMLLLyricsClient(session: session).lyrics(
            songID: candidate.id,
            metadata: candidateMetadata
        )
        return try await (payload, ttml)
    }

    private func candidate(for metadata: LyricSongMetadata) async throws
    -> NetEaseCandidate? {
        for query in LyricCandidateMatcher.searchQueries(for: metadata) {
            let candidates = try await search(query: query)
            if let index = LyricCandidateMatcher.bestCandidate(
                in: candidates.map {
                    LyricCandidate(title: $0.name, artist: $0.artist,
                                   album: $0.album,
                                   durationSeconds: $0.durationSeconds)
                },
                for: metadata
            ) {
                return candidates[index]
            }
        }
        return nil
    }

    private func search(query: String) async throws -> [NetEaseCandidate] {
        let response: NetEaseSearchResponse = try await eapi(
            "/api/search/get",
            data: ["s": query, "type": 1, "limit": 30, "offset": 0]
        )
        return Self.candidates(in: response)
    }

    static func candidates(in response: NetEaseSearchResponse) -> [NetEaseCandidate] {
        (response.result?.songs ?? []).compactMap { song in
            guard song.id > 0, !song.name.isEmpty else { return nil }
            return NetEaseCandidate(
                id: song.id,
                name: song.name,
                artist: song.artistList.map(\.name).joined(separator: ","),
                album: song.albumInfo?.name ?? "",
                durationSeconds: max(0, song.durationMS / 1_000)
            )
        }
    }

    private func lyric(id: Int) async throws -> NetEaseLyricPayload {
        do {
            let response: NetEaseLyricResponse = try await eapi(
                "/api/song/lyric/v1",
                data: [
                    "id": id, "cp": false, "tv": 0, "lv": 0, "rv": 0,
                    "kv": 0, "yv": 0, "ytv": 0, "yrv": 0,
                ]
            )
            return response.payload
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let response: NetEaseLyricResponse = try await eapi(
                "/api/song/lyric",
                data: ["id": id, "tv": -1, "lv": -1, "rv": -1, "kv": -1,
                       "_nmclfl": 1]
            )
            return response.payload
        }
    }

    private func eapi<Response: Decodable>(
        _ uri: String,
        data: [String: Any]
    ) async throws -> Response {
        var requestData = data
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        requestData["header"] = [
            "os": "ios",
            "appver": "9.0.90",
            "osver": "18.0",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "channel": "distribution",
            "requestId": "\(timestamp)_0000",
            "__csrf": "",
        ]
        requestData["e_r"] = false
        let json = try Self.jsonString(requestData)
        let message = "nobody\(uri)use\(json)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(message.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let payload = "\(uri)-36cd479b6b5-\(json)-36cd479b6b5-\(digest)"
        let encrypted = Self.aesECB(Data(payload.utf8), key: "e82ckenh8dichen8")
        guard !encrypted.isEmpty else { throw LyricSourceError.invalidResponse }
        let params = encrypted.map { String(format: "%02X", $0) }.joined()
        let path = uri.replacingOccurrences(of: "/api/", with: "/eapi/")
        guard let url = URL(string: "https://interface.music.163.com\(path)") else {
            throw LyricSourceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.httpBody = Data("params=\(Self.encodeURIComponent(params))".utf8)
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), !body.isEmpty else {
            throw LyricSourceError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: body)
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw LyricSourceError.invalidResponse
        }
        return text
    }

    private static func aesECB(_ data: Data, key: String) -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var length = 0
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { bytes in
                key.withCString { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes, kCCKeySizeAES128, nil,
                        bytes.baseAddress, data.count,
                        out.baseAddress, out.count, &length
                    )
                }
            }
        }
        guard status == kCCSuccess else { return Data() }
        output.removeSubrange(length..<output.count)
        return output
    }

    private static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct NetEaseCandidate: Hashable {
    let id: Int
    let name: String
    let artist: String
    let album: String
    let durationSeconds: Int
}

struct NetEaseSearchResponse: Decodable {
    let result: Payload?
    struct Payload: Decodable {
        let songs: [Song]?
    }
    struct Song: Decodable {
        let id: Int
        let name: String
        let ar: [Artist]?
        let artists: [Artist]?
        let al: Album?
        let album: Album?
        let dt: Int?
        let duration: Int?
        var artistList: [Artist] { ar ?? artists ?? [] }
        var albumInfo: Album? { al ?? album }
        var durationMS: Int { dt ?? duration ?? 0 }
    }
    struct Artist: Decodable { let name: String }
    struct Album: Decodable { let name: String }
}

private struct NetEaseLyricResponse: Decodable {
    let lrc: Content?
    let yrc: Content?
    let tlyric: Content?
    let ytlrc: Content?
    let romalrc: Content?
    let yromalrc: Content?
    let pureMusic: Bool?
    var payload: NetEaseLyricPayload {
        NetEaseLyricPayload(
            yrc: yrc?.lyric, lrc: lrc?.lyric,
            translatedYRC: ytlrc?.lyric, translatedLRC: tlyric?.lyric,
            romanizedYRC: yromalrc?.lyric, romanizedLRC: romalrc?.lyric,
            isPureMusic: pureMusic == true
        )
    }
    struct Content: Decodable { let lyric: String? }
}
