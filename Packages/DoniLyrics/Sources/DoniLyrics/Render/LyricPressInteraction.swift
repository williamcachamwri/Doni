import SwiftUI

public struct LyricPressInteraction<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public let isSelected: Bool
    public let allowsTap: Bool
    public let allowsLongPress: Bool
    public let onTap: () -> Void
    public let onLongPress: () -> Void
    private let content: (Double) -> Content

    @State private var suppressesTap = false

    public init(
        isSelected: Bool,
        allowsTap: Bool = true,
        allowsLongPress: Bool = true,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        @ViewBuilder content: @escaping (Double) -> Content
    ) {
        self.isSelected = isSelected
        self.allowsTap = allowsTap
        self.allowsLongPress = allowsLongPress
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.content = content
    }

    public var body: some View {
        Button(action: performTap) {
            LyricPressLabel(
                content: content
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            LyricPressButtonStyle(
                isSelected: isSelected,
                reducesMotion: accessibilityReduceMotion
            )
        )
        .simultaneousGesture(
            LongPressGesture()
            .onEnded { didComplete in
                guard didComplete, allowsLongPress else { return }
                suppressesTap = true
                onLongPress()
            },
            isEnabled: allowsLongPress
        )
        .onChange(of: isSelected) { _, isSelected in
            if !isSelected {
                suppressesTap = false
            }
        }
        .allowsHitTesting(allowsTap || allowsLongPress)
    }

    private func performTap() {
        guard allowsTap else { return }
        guard !suppressesTap else {
            suppressesTap = false
            return
        }
        onTap()
    }
}

private struct LyricPressLabel<Content: View>: View {
    @Environment(\.lyricPressBackgroundProgress)
    private var backgroundProgress

    public let content: (Double) -> Content

    public var body: some View {
        content(backgroundProgress)
    }
}

private struct LyricPressButtonStyle: ButtonStyle {
    public let isSelected: Bool
    public let reducesMotion: Bool

    public func makeBody(configuration: Configuration) -> some View {
        LyricPressButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected,
            reducesMotion: reducesMotion
        )
    }
}

private struct LyricPressButtonStyleBody<Label: View>: View {
    public let label: Label
    public let isPressed: Bool
    public let isSelected: Bool
    public let reducesMotion: Bool

    @State private var scale: CGFloat = 1
    @State private var backgroundProgress = 0.0

    public var body: some View {
        label
            .environment(
                \.lyricPressBackgroundProgress,
                isSelected ? 1 : backgroundProgress
            )
            .scaleEffect(scale, anchor: .center)
            .onAppear {
                updatePressedState(isPressed, animated: false)
            }
            .onChange(of: isPressed) { _, isPressed in
                updatePressedState(isPressed, animated: true)
            }
            .onChange(of: isSelected) { _, isSelected in
                updateSelectedState(isSelected)
            }
    }

    private func updatePressedState(
        _ isPressed: Bool,
        animated: Bool
    ) {
        guard animated, !reducesMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scale =
                    isPressed
                        ? LyricPressAnimation.pressedScale
                        : 1
                backgroundProgress =
                    isPressed || isSelected
                        ? 1
                        : 0
            }
            return
        }

        if isPressed {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                backgroundProgress = 1
            }
            withAnimation(
                .easeInOut(
                    duration: LyricPressAnimation.pressDuration
                )
            ) {
                scale = LyricPressAnimation.pressedScale
            }
        } else {
            withAnimation(
                .easeInOut(
                    duration: LyricPressAnimation.releaseDuration
                )
            ) {
                scale = 1
            }
            guard !isSelected else { return }
            withAnimation(
                .easeIn(
                    duration: LyricPressAnimation
                        .backgroundReleaseDuration
                )
            ) {
                backgroundProgress = 0
            }
        }
    }

    private func updateSelectedState(_ isSelected: Bool) {
        if isSelected {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                backgroundProgress = 1
            }
        } else {
            withAnimation(
                reducesMotion
                    ? nil
                    : .easeInOut(
                        duration: LyricPressAnimation.releaseDuration
                    )
            ) {
                scale = 1
            }
            withAnimation(
                reducesMotion
                    ? nil
                    : .easeIn(
                        duration: LyricPressAnimation
                            .backgroundReleaseDuration
                    )
            ) {
                backgroundProgress = 0
            }
        }
    }
}

private enum LyricPressAnimation {
    public static let pressedScale: CGFloat = 0.96
    public static let pressDuration: TimeInterval = 0.10
    public static let releaseDuration: TimeInterval = 0.38
    public static let backgroundReleaseDuration: TimeInterval = 0.28
}

private struct LyricPressBackgroundProgressKey: EnvironmentKey {
    public static let defaultValue = 0.0
}

private extension EnvironmentValues {
    var lyricPressBackgroundProgress: Double {
        get { self[LyricPressBackgroundProgressKey.self] }
        set { self[LyricPressBackgroundProgressKey.self] = newValue }
    }
}
