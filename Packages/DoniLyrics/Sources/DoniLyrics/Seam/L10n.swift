import Foundation

/// The strings the lyrics screens say out loud. The reference keeps them in a
/// `.strings` catalog with English and Chinese; Doni's interface is Vietnamese, so the
/// same keys carry Vietnamese values here and the copied views ask for them by the same
/// keys they were written with.
nonisolated enum L10n {
    private static let strings: [String: String] = [
        "ui.common.cancel": "Huỷ",
        "ui.common.custom": "Tuỳ chỉnh",
        "ui.common.off": "Tắt",
        "ui.common.replace": "Thay thế",
        "ui.common.spoken_separator": ", ",
        "ui.common.title_detail_separator": " — ",
        "ui.lyrics.accessibility.romanization": "Phiên âm: %@",
        "ui.lyrics.accessibility.translation": "Bản dịch: %@",
        "ui.lyrics.browse_focus": "Đang xem dòng này",
        "ui.lyrics.current_browse_focus": "Đang phát, đang xem dòng này",
        "ui.lyrics.empty": "Không có lời bài hát",
        "ui.lyrics.interaction_disabled_hint": "Thao tác với lời đang tắt trong Cài đặt",
        "ui.lyrics.loading": "Đang tải lời",
        "ui.lyrics.long_press_share_hint": "Nhấn giữ để chia sẻ lời này",
        "ui.lyrics.share.character_count": "%ld / %ld ký tự",
        "ui.lyrics.share.character_limit_message":
            "Phần lời đang chọn vượt quá giới hạn %ld ký tự nên không chia sẻ được.",
        "ui.lyrics.share.excerpt": "Trích lời: %@",
        "ui.lyrics.share.excerpt_song": "Trích lời · %@",
        "ui.lyrics.share.none_selected": "Chưa chọn dòng lời nào",
        "ui.lyrics.share.replace_confirmation": "Thay thế phần đã chọn trước?",
        "ui.lyrics.share.select_hint": "Nhấn vào một dòng lời để chia sẻ",
        "ui.lyrics.share.selected_lines": "Đã chọn %ld dòng lời",
        "ui.lyrics.share.title": "Chia sẻ lời",
        "ui.lyrics.tap_seek_hint": "Nhấn để tua đến dòng này",
        "ui.lyrics.tap_seek_long_press_share": "Nhấn để tua đến dòng này; nhấn giữ để chia sẻ",
        "ui.player.now_playing": "Đang phát",
        "ui.settings.font_weight.bold": "Đậm",
        "ui.settings.font_weight.heavy": "Rất đậm",
        "ui.settings.font_weight.light": "Nhẹ",
        "ui.settings.font_weight.medium": "Vừa",
        "ui.settings.font_weight.regular": "Thường",
        "ui.settings.font_weight.semibold": "Bán đậm",
        "ui.settings.lyrics.auxiliary.all_lines": "Tất cả dòng lời",
        "ui.settings.lyrics.auxiliary.focused_line": "Chỉ dòng đang hát",
        "ui.settings.lyrics.interlude.automatic": "Tự động (cả ước lượng từ LRC)",
        "ui.settings.lyrics.interlude.automatic.detail":
            "Dùng timing YRC chính xác khi có, và ước lượng thời điểm hết dòng theo độ dài chữ với lời LRC thường.",
        "ui.settings.lyrics.interlude.hidden.detail":
            "Không chèn khoảng mở đầu hay gián đoạn.",
        "ui.settings.lyrics.interlude.precise": "Chỉ timeline chính xác",
        "ui.settings.lyrics.interlude.precise.detail":
            "Chỉ phát hiện khoảng nhạc cụ dựa trên thời điểm kết thúc âm tiết YRC.",
        "ui.settings.lyrics.lift.character": "Nâng theo ký tự",
        "ui.settings.lyrics.lift.word": "Nâng theo từ",
        "ui.settings.lyrics.long_syllable.character": "Phát hiện theo ký tự",
        "ui.settings.lyrics.long_syllable.word": "Phát hiện theo từ",
        "ui.settings.lyrics.motion_preset.apple_music_26": "Apple Music 26",
        "ui.settings.lyrics.motion_preset.apple_music_26.mobile_detail":
            "Dùng font, khoảng cách, màu, độ mờ và nhịp đuổi từng dòng của iOS 26.6.",
        "ui.settings.lyrics.motion_preset.custom.detail":
            "Dùng các thông số tự chỉnh: typography, tiêu điểm, đuôi dòng, bắt kịp, nảy và layout.",
    ]

    static func string(_ key: String, comment: StaticString? = nil) -> String {
        // The app's catalog, not a table of our own. The copied views ask for some strings by key
        // through this seam and for others by key straight into SwiftUI's own localized initializers,
        // and those two paths have to agree: one catalog is the only way a screen cannot end up
        // half in Russian and half in Vietnamese. `value:` is the Vietnamese we transcribed, so a key
        // the catalog has never heard of still says what the reference wrote.
        NSLocalizedString(key, bundle: .main, value: strings[key] ?? key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }

    static func joined(_ values: [String], separatorKey: String) -> String {
        values.joined(separator: string(separatorKey))
    }
}
