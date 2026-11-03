import SwiftUI

/// The item list — the module every real Telegram settings screen is built from.
///
/// `ItemListUI` writes its sizes as ratios of two bases rather than as literals
/// (`/ 17.0 * 15.0` at `ItemListTextItem.swift:169`, `* 12.0 / 13.0` at
/// `ItemListSectionHeaderItem.swift:188`), and those ratios are what fix the bases at 17 and 13.
/// `Docs/design-tokens.md`, "Settings — the clothing the item list wears".
public enum TelegramSettingsMetrics {
    /// `verticalInset = 15.0` in the glass style (`ItemListActionItem.swift:189`); the row is then
    /// `titleLayout.size.height + verticalInset * 2.0` (`:200`), so the padding, not a total, is
    /// what Doni expresses.
    public static let rowVerticalInset: CGFloat = 15
    /// `verticalInset = 13.0` the moment the row carries a second line
    /// (`ItemListDisclosureItem.swift:525-528`), over `titleSpacing = 1.0` (`:546`).
    public static let rowVerticalInsetWithSecondary: CGFloat = 13
    public static let rowLineSpacing: CGFloat = 1
    /// `leftInset = 16.0 + params.leftInset` (`:237`) — the same 16 every other band in the app
    /// uses, and where the hairline under a row starts too (`bottomStripeInset`, `:282`). In the
    /// plain style the rule then runs from there to the edge (`:253`); only the grouped card stops
    /// it 16 short (`:298`), and Doni does not draw one.
    public static let rowLeftInset: CGFloat = 16
    /// `detailRightInset = 20.0 + params.rightInset` (`ItemListDisclosureItem.swift:503`) — a value
    /// is further in than a title is, because nothing may sit flush with the edge.
    public static let valueRightInset: CGFloat = 20
    /// `leftInset = 15.0 + params.leftInset` (`ItemListSectionHeaderItem.swift:180`). A header is
    /// one point off the row's 16; the reference is consistent about being inconsistent here.
    public static let headerLeftInset: CGFloat = 15
    /// `height: 7.0` for the title's own origin inside a band of `textHeight + 13.0` (`:252`, `:228`).
    public static let headerTitleY: CGFloat = 7
    public static let headerBandPadding: CGFloat = 13
    /// `insets.top += 24.0`, and 28 once a section has ended above it (`:231`, `:233`).
    public static let sectionGap: CGFloat = 24
    public static let sectionGapAfterSection: CGFloat = 28
    /// `insets.bottom += 22.0` for the last row of a plain list (`ItemListItem.swift:90`); the same
    /// 22 is what a section break costs when the list is not grouped (`:84`).
    public static let plainSectionEnd: CGFloat = 22
}

public enum TelegramSettingsTypography {
    /// `Font.regular(item.presentationData.fontSize.itemListBaseFontSize)`
    /// (`ItemListActionItem.swift:159`) — the same base the chat list is drawn at, which the photo
    /// measures as 14 rather than the 17 the module's ratios are written against.
    public static let rowTitle = Font.system(size: TelegramLibraryMetrics.scaled(17), weight: .regular)
    /// `Font.regular(floor(itemListBaseFontSize * 15.0 / 17.0))` (`ItemListDisclosureItem.swift:467`).
    public static let value = Font.system(size: TelegramLibraryMetrics.scaled(15), weight: .regular)
    /// `Font.regular(itemListBaseFontSize * 14.0 / 17.0)` (`ItemListSwitchItem.swift:290`).
    public static let secondary = Font.system(size: TelegramLibraryMetrics.scaled(14), weight: .regular)
    /// `Font.regular(itemListBaseHeaderFontSize)` (`ItemListSectionHeaderItem.swift:183`), which is
    /// itself `floor(itemListBaseFontSize × 13/17)` (`ItemListItem.swift:173`).
    public static let sectionHeader = Font.system(size: TelegramLibraryMetrics.scaled(13), weight: .regular)
}
