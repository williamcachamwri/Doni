import Foundation

struct AMLLLyricsClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lyrics(songID: Int, metadata: LyricSongMetadata) async -> String? {
        guard let url = URL(string: "https://amlldb.bikonoo.com/ncm-lyrics/\(songID).ttml")
        else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad,
                                 timeoutInterval: 15)
        request.setValue("application/ttml+xml, application/xml;q=0.9, text/xml;q=0.8",
                         forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8),
              text.contains("<tt"), text != "歌词不存在",
              AMLLLyricMetadata(ttml: text)?.matches(song: metadata) != false
        else { return nil }
        return text
    }
}
