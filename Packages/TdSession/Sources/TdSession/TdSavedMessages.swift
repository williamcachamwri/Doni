import Foundation

/// The chat this account keeps for itself, where Doni's Cloud Music lives.
///
/// Saved Messages is not special in TDLib's interface: it is the private chat with the account's own
/// user id — "Call `createPrivateChat` with `getOption("my_id")` and open the chat" (`td_api.tl:10301`).
/// After that it is ordinary chat calls: the same `getChatHistory` (`:12758`) a channel walk uses, and
/// a `sendMessage` (`:13143`) whose document is a local path TDLib uploads on the way.
///
/// Nothing here invents a second storage: a song in Saved Messages *is* the copy, and the bytes the
/// user uploaded are dropped as soon as Telegram has them.
public struct TdSavedMessages: Sendable {
    public enum Failure: Error, Equatable {
        case noUserId
        case noChat
        /// TDLib answered a request with something that is not what the request makes.
        case unexpectedResponse(String)
        /// The send came back with something other than a `message`. Its own case because the caller
        /// has to keep the local file in that case rather than delete it.
        case notAMessage(String)
    }

    private let flow: TdLoginFlow

    public init(flow: TdLoginFlow) {
        self.flow = flow
    }

    /// Which of the two calls refused, in TDLib's own words.
    ///
    /// A result rather than an optional: a missing chat id has four causes, and the listener can only
    /// act on the right one if the app kept which step said no.
    public enum ChatFailure: Error, Equatable, Sendable {
        case noUserId(String)
        case noChat(String)
    }

    /// The chat id, created if the account has never opened it.
    ///
    /// `userId` is the current user's id, which the session already has from `getMe` — the same number
    /// `getOption("my_id")` answers with. The option stays as the fallback for a caller that has no
    /// account in hand.
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
            // TDLib's own bytes are quoted back rather than summarised: "no value", an unexpected
            // shape and a value of zero are three different bugs that read the same without them.
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
    /// store — which is why this returns `TdHistoryPage`: a Saved Messages song and a channel song are
    /// the same row, and two code paths is how they disagree about "downloaded".
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

    /// Sends one file as a document, and answers with the message id Telegram gave it.
    ///
    /// `sendMessage` is the upload: TDLib reads `inputFileLocal` (`td_api.tl:340`), uploads it, and
    /// puts the resulting file — its own `file_id`, its durable `file_unique_id` — in the message it
    /// returns, so there is no separate `uploadFile` to get wrong and no second copy of the bytes.
    ///
    /// The id is all this returns, and it is enough: a post that has just left the phone can still
    /// have an absent `remote.unique_id` (`td_api.tl:318`), and a row is keyed by that identity — a
    /// guessed one lists the song twice the moment the chat is read again. So the answer is that the
    /// send was accepted, and the library waits for the chat's own history.
    ///
    /// The caption is the file's own name: a document post has no title field, so without it the row
    /// is named by nothing but the song's hash.
    public func upload(chatId: Int64, path: String, caption: String) async throws -> Int64 {
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
        // `message` (`td_api.tl:4063`) is the only answer that means the post exists; nothing else
        // about it is decoded here.
        guard answer.type == "message", let id = answer["id"]?.int, id != 0 else {
            throw Failure.notAMessage(Self.quote(answer))
        }
        return id
    }

    /// Takes messages out of the chat, and with them the songs Cloud Music lists.
    ///
    /// `revoke: false` (`td_api.tl:13222-13226`): Saved Messages is a chat with nobody but yourself,
    /// so "for all members" would be a second name for the same act — and it is the flag that makes
    /// this request dangerous anywhere else.
    ///
    /// TDLib answers `Ok` and then sends `updateDeleteMessages`; the listener acts on the update
    /// rather than on this reply, so a delete Telegram refused does not silently empty a row.
    public func delete(chatId: Int64, messageIds: [Int64]) async throws {
        _ = try await flow.request(
            "deleteMessages",
            [
                "chat_id": .int(chatId),
                "message_ids": .array(messageIds.map(TdJSON.int)),
                "revoke": .bool(false)
            ]
        )
    }
}
