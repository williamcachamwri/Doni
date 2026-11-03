import Foundation

/// The 13 fields of `tdlibParameters` (`td_api.tl:41`) for a normal install.
///
/// `use_message_database` and `use_chat_info_database` have to be on: the whole
/// product is a local index of a channel's audio posts. `use_file_database` is
/// on so TDLib remembers which files are already downloaded.
public struct TdParameters: Sendable {
    public var apiId: Int32
    public var apiHash: String
    public var databaseDirectory: String
    public var filesDirectory: String
    public var deviceModel: String
    public var systemVersion: String
    public var applicationVersion: String
    public var systemLanguageCode: String = "vi"
    public var useTestDc: Bool = false
    public var useFileDatabase: Bool = true
    public var useChatInfoDatabase: Bool = true
    public var useMessageDatabase: Bool = true
    public var useSecretChats: Bool = false
    public var enableStorageOptimizer: Bool = false
    public var ignoreFileNames: Bool = false

    public init(
        apiId: Int32,
        apiHash: String,
        databaseDirectory: String,
        filesDirectory: String,
        deviceModel: String,
        systemVersion: String,
        applicationVersion: String
    ) {
        self.apiId = apiId
        self.apiHash = apiHash
        self.databaseDirectory = databaseDirectory
        self.filesDirectory = filesDirectory
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.applicationVersion = applicationVersion
    }

    public var json: TdJSON {
        .object([
            "@type": .string("tdlibParameters"),
            "use_test_dc": .bool(useTestDc),
            "database_directory": .string(databaseDirectory),
            "files_directory": .string(filesDirectory),
            "use_file_database": .bool(useFileDatabase),
            "use_chat_info_database": .bool(useChatInfoDatabase),
            "use_message_database": .bool(useMessageDatabase),
            "use_secret_chats": .bool(useSecretChats),
            "api_id": .int(Int64(apiId)),
            "api_hash": .string(apiHash),
            "system_language_code": .string(systemLanguageCode),
            "device_model": .string(deviceModel),
            "system_version": .string(systemVersion),
            "application_version": .string(applicationVersion),
            "enable_storage_optimizer": .bool(enableStorageOptimizer),
            "ignore_file_names": .bool(ignoreFileNames),
        ])
    }
}

/// Where the TDLib database key comes from.
///
/// The implementation in the app reads it from the Keychain and creates it on
/// first run — the session database in Application Support is the user's
/// logged-in Telegram session, so it is only unreadable while the device is
/// locked if the key is not sitting next to it in a plist.
public protocol TdDatabaseKeyProviding: Sendable {
    /// Base64: the JSON interface encodes TDLib's `bytes` fields that way
    /// (`checkDatabaseEncryptionKey encryption_key:bytes`, `td_api.tl:4032`).
    ///
    /// Throws, because the real implementation reads the Keychain and a
    /// hardware keystore can genuinely refuse.
    func databaseEncryptionKey() throws -> String
}
