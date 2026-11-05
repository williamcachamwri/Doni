import SwiftUI
import TelegramDesignSystem

/// The language picker, in the shape every other Settings screen wears.
///
/// Choosing writes `AppleLanguages`, which the system reads when the process starts — so the screen
/// says out loud that the change lands on the next launch. A control that appears to do nothing for
/// thirty seconds is the one thing here a user would reasonably read as broken.
struct LanguageView: View {
    @State private var chosen = DoniLanguage.current

    var body: some View {
        ScrollView {
            VStack(spacing: MusicSettingsMetrics.sectionSpacing) {
                card {
                    ForEach(Array(DoniLanguage.allCases.enumerated()), id: \.element) { index, language in
                        if index > 0 { divider }
                        Button {
                            chosen = language
                            DoniLanguage.apply(language)
                        } label: {
                            HStack(spacing: MusicSettingsMetrics.rowIconGap) {
                                Text(language.nativeName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if language == chosen {
                                    Image(systemName: "checkmark")
                                        .font(MusicSettingsMetrics.chevronFont)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, MusicSettingsMetrics.rowPaddingH)
                            .padding(.vertical, MusicSettingsMetrics.rowPaddingV)
                            .frame(minHeight: MusicSettingsMetrics.rowMinHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Doni đổi ngôn ngữ khi bạn mở lại app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MusicSettingsMetrics.rowPaddingH)
            }
            .padding(.horizontal, MusicSettingsMetrics.sidePadding)
            .padding(.top, MusicSettingsMetrics.contentTop)
            .padding(.bottom, MusicSettingsMetrics.contentBottom)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Ngôn ngữ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var divider: some View {
        Divider().padding(.leading, MusicSettingsMetrics.rowPaddingH)
    }
}

#Preview {
    NavigationStack {
        LanguageView()
    }
    .tint(MusicTint.accent)
    .preferredColorScheme(.dark)
}
