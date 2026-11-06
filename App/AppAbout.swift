import SwiftUI

/// The app's own mark: the home-screen icon, at whatever side a surface draws it.
///
/// The corner radius is 22.5 % of the side, which is the proportion of the iOS icon mask itself, so
/// this tile and the real icon on the springboard are the same shape rather than two different ones.
struct DoniLogo: View {
    var side: CGFloat = 72

    var body: some View {
        Image("DoniMark")
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .accessibilityLabel("Doni")
    }
}

/// The words About says in every shell. The phone draws them as list sections, the desktop as cards
/// inside its settings panel, but a licence line or a copyright year written twice is a line that
/// can drift — so both shells read them from here.
enum AppAbout {
    static let copyright = "© 2026 williamcachamwri"
    static let telegramHandle = "@williamcachamwri"
    static let telegramURL = URL(string: "https://t.me/w1lliamcachamwri")!

    struct Licence: Identifiable {
        let name: String
        let licence: String
        var id: String { name }
    }

    /// Doni is GPL-3.0 because the lyrics screen and several feed views came from GPLv3 MeloX; TDLib
    /// and OpenSSL are linked, Telegram-iOS was only measured, and the lyrics sources are web
    /// requests rather than code.
    static let licences: [Licence] = [
        Licence(name: "Doni", licence: "GPL-3.0"),
        Licence(name: "TDLib", licence: "Boost Software License 1.0"),
        Licence(name: "OpenSSL", licence: "Apache-2.0"),
        Licence(name: "SQLite", licence: "Public domain"),
        Licence(name: "MeloX", licence: "GPL-3.0"),
        Licence(name: "Telegram-iOS", licence: "GPL-2.0"),
        Licence(name: "lrclib · NetEase · AMLL · QQ Music", licence: "Web API"),
    ]
}
