import Foundation

/// The chat this account keeps for itself, which is where Doni's Cloud Music lives.
///
/// Saved Messages is not a special thing in TDLib's interface: it is the private chat with the
/// account's own user id, and the schema says so in the one place a Saved Messages link is
/// described — "Call `createPrivateChat` with `getOption("my_id")` and open the chat"
/// (`td_api.tl:10301`). So the number is asked for once, the chat is created once, and everything
/// after that is an ordinary chat call: the same `getChatHistory` (`:12758`) a channel walk uses,
/// and a `sendMessage` (`:13143`) whose document is a local path TDLib uploads on the way.
///
/// Nothing here invents a second storage. A song in Saved Messages *is* the copy: the phone keeps
/// only what streaming has needed so far, in TDLib's own file cache, and the bytes the user
/// uploaded are dropped as soon as Telegram has them.
public struct TdSavedMessages: Sendable {
    public enum Failure: Error, Equatable {
        case noUserId
        case noChat
        /// The message went out and TDLib answered with something that is not it. Said as its own
        /// case because the caller has to keep the local file in that case rather than delete it.
        case unexpectedResponse(String)
    }

    private let flow: TdLoginFlow

    public init(flow: TdLoginFlow) {
        self.flow = flow
    }

    /// Which of the two calls refused, in TDLib's own words.
    ///
    /// This is a result rather than an optional because the first build answered `nil` for every
    /// failure and the screen turned that into "you are not signed in" — on a phone that was
    /// obviously signed in, playing a song. A missing chat id has four causes and the listener can
    /// only act on the right one if the app kept which step said no.
    public enum ChatFailure: Error, Equatable, Sendable {
        case noUserId(String)
        case noChat(String)
    }

    /// The chat id, created if the account has never opened it.
    ///
    /// `userId` is the current user's id, which the session already has from `getMe` — it is the
    /// same number `getOption("my_id")` answers with, and asking for it a second time is how the
    /// first build managed to lose the chat. The option is still the fallback, for a caller that has
    /// no account in hand.
    public func chatId(userId known: Int64? = nil) async -> Result<Int64, ChatFailure> {
        let userId: Int64
        if let known, known != 0 {
            userId = known
        } else {
            let option: TdJSON
            do {
                option = try await flow.request("getOption", ["name": .string("my_id")])
            } catch {
                return .failure(.noUserId("\(error)"))
            }
            // TDLib's own bytes are quoted back on failure rather than summarised: "no value", "a
            // value of a shape nobody expected" and "a value of zero" are three different bugs and
            // all three read the same without what was sent.
            guard let answer = option["value"]?.int else {
                return .failure(.noUserId("no integer in \(Self.quote(option))"))
            }
            guard answer != 0 else { return .failure(.noUserId("my_id is 0")) }
            userId = answer
        }
        let chat: TdJSON
        do {
            chat = try await flow.request(
                "createPrivateChat", ["user_id": .int(userId), "force": .bool(false)]
            )
        } catch {
            return .failure(.noChat("\(error)"))
        }
        guard chat.type == "chat", let id = chat["id"]?.int, id != 0 else {
            return .failure(.noChat(Self.quote(chat)))
        }
        return .success(id)
    }

    /// A response in a sentence: short, and enough to see the shape of.
    private static func quote(_ json: TdJSON) -> String {
        let text = json.serialized ?? "unreadable"
        return text.count > 140 ? String(text.prefix(140)) + "…" : text
    }

    /// One page of the chat's newest posts, in the shape the channel indexer already writes to the
    /// store — which is the whole reason this returns `TdHistoryPage`: a Saved Messages song and a
    /// channel song are the same row, and two code paths for them is how one of them gets a
    /// different idea of what "downloaded" means.
    public func page(chatId: Int64, cursor: Int64 = 0) async throws -> TdHistoryPage {
        let answer = try await flow.request(
            "getChatHistory",
            [
                "chat_id": .int(chatId),
                "from_message_id": .int(cursor),
                "offset": .int(0),
                "limit": .int(Int64(TdChannelReader.pageSize)),
                "only_local": .bool(false)
            ]
        )
        guard answer.type == "messages", let items = answer["messages"]?.array else {
            throw Failure.unexpectedResponse(answer.type ?? "no @type")
        }
        return TdHistoryPage(messages: items, totalCount: answer["total_count"]?.int.map { Int($0) })
    }

    /// Sends one file as a document, and answers with the message Telegram made.
    ///
    /// `sendMessage` is the upload: TDLib reads `inputFileLocal` (`td_api.tl:340`), uploads it, and
    /// puts the resulting file — with its own `file_id` and its durable `file_unique_id` — in the
    /// message it returns. There is no separate `uploadFile` request to get wrong, and no second
    /// copy of the bytes to keep track of.
    ///
    /// The caption is the file's own name. A document post has no title field the way an audio post
    /// does, so without a caption the row would be named by nothing but the song's hash — and the
    /// name the user picked at the file panel is the one thing worth carrying over.
    public func upload(chatId: Int64, path: String, caption: String) async throws -> TdTrack {
        let answer = try await flow.request(
            "sendMessage",
            [
                "chat_id": .int(chatId),
                "topic_id": .null,
                "reply_to": .null,
                "options": .null,
                "reply_markup": .null,
                "input_message_content": .object([
                    "@type": .string("inputMessageDocument"),
                    "document": .object([
                        "@type": .string("inputDocument"),
                        "document": .object([
                            "@type": .string("inputFileLocal"),
                            "path": .string(path)
                        ]),
                        "thumbnail": .null,
                        "disable_content_type_detection": .bool(false)
                    ]),
                    "caption": .object([
                        "@type": .string("formattedText"),
                        "text": .string(caption),
                        "entities": .array([])
                    ])
                ])
            ]
        )
        guard answer.type == "message", let track = TdTrack(message: answer) else {
            throw Failure.unexpectedResponse(answer.type ?? "no @type")
        }
        return track
    }
}
