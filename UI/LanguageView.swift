import SwiftUI
import TelegramDesignSystem

/// The language picker, in the shape every other Settings screen wears.
///
/// Choosing writes `AppleLanguages`, which the system reads once when the process starts. There is
/// no way to re-resolve every string already handed to every view on screen, so the screen does not
/// pretend: it says the app has to be reopened and gives exactly one way to do that. A picker that
/// appeared to do nothing for the next thirty seconds is what a user would read as broken.
struct LanguageView: View {
    @State private var chosen = DoniLanguage.current
    @State private var pending: DoniLanguage?

    var body: some View {
        ScrollView {
            VStack(spacing: MusicSettingsMetrics.sectionSpacing) {
                card {
                    ForEach(Array(DoniLanguage.allCases.enumerated()), id: \.element) { index, language in
                        if index > 0 { divider }
                        Button {
                            chosen = language
                            DoniLanguage.apply(language)
                            pending = language
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
            }
            .padding(.horizontal, MusicSettingsMetrics.sidePadding)
            .padding(.top, MusicSettingsMetrics.contentTop)
            .padding(.bottom, MusicSettingsMetrics.contentBottom)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Ngôn ngữ")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Đổi ngôn ngữ", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            // One button, and it ends the process. An app that only *asks* to be reopened leaves the
            // reader deciding how — and swiping away from the app switcher is the one gesture that
            // may not actually kill it, which is how a language change looks like it never worked.
            Button("Thoát ra") { exit(EXIT_SUCCESS) }
        } message: {
            Text(localized("Doni sẽ mở lại bằng %@.", pending?.nativeName ?? ""))
        }
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
