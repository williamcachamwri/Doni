import SwiftUI

/// `theme.list.*` — the colours the authorization screens read. Login is not a chat screen:
/// `AuthorizationSequenceController` sets its background to `list.plainBackgroundColor` and every node
/// takes its text from the same block. Sources: `Docs/design-tokens.md`, "Palette — day, `list.*`".
public struct TelegramListPalette: Sendable {
    public let background: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let disabledText: Color
    public let accent: Color
    public let destructive: Color
    public let placeholder: Color
    public let separator: Color
    public let checkFill: Color
    public let checkForeground: Color
    /// `plainBackground` mixed with `disabledText` at 0.15, as `SolidRoundedButtonTheme` does for a
    /// disabled button: 255·0.85 + 142·0.15 ≈ 238 per channel, so `#eeeeee`.
    public let disabledCheckFill: Color
    /// `itemDisclosureActions.constructive.fillColor`, which the code boxes take on for the
    /// ~0.4 s after an accepted code.
    public let constructive: Color

    public init(
        background: Color,
        primaryText: Color,
        secondaryText: Color,
        disabledText: Color,
        accent: Color,
        destructive: Color,
        placeholder: Color,
        separator: Color,
        checkFill: Color,
        checkForeground: Color,
        disabledCheckFill: Color,
        constructive: Color
    ) {
        self.background = background
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.disabledText = disabledText
        self.accent = accent
        self.destructive = destructive
        self.placeholder = placeholder
        self.separator = separator
        self.checkFill = checkFill
        self.checkForeground = checkForeground
        self.disabledCheckFill = disabledCheckFill
        self.constructive = constructive
    }

    public static let day = TelegramListPalette(
        background: Color(rgb: 0xffffff),
        primaryText: Color(rgb: 0x000000),
        secondaryText: Color(rgb: 0x8e8e93),
        disabledText: Color(rgb: 0x8e8e93),
        accent: Color(rgb: 0x0088ff),
        destructive: Color(rgb: 0xff3b30),
        placeholder: Color(rgb: 0xc8c8ce),
        separator: Color(rgb: 0xc8c7cc),
        checkFill: Color(rgb: 0x0088ff),
        checkForeground: Color(rgb: 0xffffff),
        disabledCheckFill: Color(rgb: 0xeeeeee),
        constructive: Color(rgb: 0x00c900)
    )

    /// The same block in the appearance Doni ships in: the sequence is the music app's front door, so it
    /// wears the shell's black (`chatListBackground`, `TelegramPalette.dark`) and accent
    /// (`MusicTint.accent`, MeloX's `.tint(.red)` in dark) with white type; every other value is the dark
    /// sibling already in `TelegramPalette.dark`. `disabledCheckFill` derives as the day one does:
    /// 0·0.85 + 141·0.15 ≈ 21 per channel.
    public static let night = TelegramListPalette(
        background: Color(rgb: 0x000000),
        primaryText: Color(rgb: 0xffffff),
        secondaryText: Color(rgb: 0x98989e),
        disabledText: Color(rgb: 0x8d8e93),
        accent: MusicTint.accent,
        destructive: Color(rgb: 0xeb5545),
        placeholder: Color(rgb: 0x8f8f8f),
        separator: Color(rgb: 0x545458, alpha: 0.55),
        checkFill: MusicTint.accent,
        checkForeground: Color(rgb: 0xffffff),
        disabledCheckFill: Color(rgb: 0x151516),
        constructive: Color(rgb: 0x30d15b)
    )
}

/// Typography of the authorization screens, in Telegram's own weights: `Font.light(30.0)` is the phone
/// title with the keyboard closed and `Font.bold(28.0)` the same label once it opens, so a single
/// `.title` would be wrong in both states.
public enum TelegramLoginTypography {
    public static let phoneTitleIdle = Font.system(size: 30, weight: .light)
    public static let phoneTitleActive = Font.system(size: 28, weight: .bold)
    public static let title = Font.system(size: 28, weight: .semibold)
    public static let subtitle = Font.system(size: 17, weight: .regular)
    /// 20 pt is what the dial code, the number and the password are typed at.
    public static let field = Font.system(size: 20, weight: .regular)
    public static let link = Font.system(size: 17, weight: .regular)
    public static let footnote = Font.system(size: 13, weight: .regular)
    public static let digit = Font.system(size: 23, weight: .regular, design: .monospaced)
    public static let digitCompact = Font.system(size: 20, weight: .regular, design: .monospaced)
    public static let buttonTitle = Font.system(size: 15, weight: .bold, design: .rounded)
}

/// Geometry of the authorization screens; `Docs/design-tokens.md`, "Login (authorization sequence)"
/// states the line each number was read from.
public enum TelegramLoginMetrics {
    public static let horizontalInset: CGFloat = 24
    public static let topInset: CGFloat = 18
    /// Where the reference stands its 100×100 `IntroPhone` sticker (`AuthorizationSequencePhoneEntryControllerNode.swift:627`,
    /// `Docs/design-tokens.md:204`); Doni ships no Lottie, so the app's own mark wears that slot.
    public static let crestSide: CGFloat = 100
    /// Doni's own: the reference swaps 30 pt light type for 28 pt bold when the keyboard comes up;
    /// the mark tucks instead, so the field block never has to move.
    public static let crestTuckedSide: CGFloat = 64
    /// The sequence's own 32 pt rhythm (`subtitleToField` is 30, the password gap 32).
    public static let crestToTitle: CGFloat = 32
    public static let titleToSubtitle: CGFloat = 18
    public static let subtitleToField: CGFloat = 30
    public static let fieldToResend: CGFloat = 50
    /// Gap between the button and the top of the keyboard, or the safe area without one.
    public static let buttonToBottom: CGFloat = 24
    public static let buttonHeight: CGFloat = 50
    public static let buttonCornerRadius: CGFloat = 25

    public static let countryRowHeight: CGFloat = 57
    public static let numberRowHeight: CGFloat = 58
    /// Both rows sit at their own offset, not the content inset: the dial code 18 pt from the screen
    /// edge, the digits 107 pt, so the columns line up under the mask Telegram draws them with.
    public static let dialCodeLeading: CGFloat = 18
    public static let numberLeading: CGFloat = 107
    /// The country title is inset a further 16 inside the content band.
    public static let countryLeading: CGFloat = 40
    public static let countryChevronWidth: CGFloat = 10
    public static let plainFieldHeight: CGFloat = 44

    public static let codeBoxWidth: CGFloat = 43
    public static let codeBoxHeight: CGFloat = 51
    public static let codeBoxCompactWidth: CGFloat = 37
    public static let codeBoxCompactHeight: CGFloat = 44
    public static let codeBoxSpacing: CGFloat = 15
    public static let codeBoxCornerRadius: CGFloat = 15

    /// The box size a row of `digits` boxes must use to live inside `available`. The reference picks by
    /// phone width, but 43 pt boxes 15 apart are 333 pt at six digits and 391 at seven, so a width rule
    /// alone lets a longer code draw past both edges.
    public static func fitCodeBoxWidth(digits: Int, available: CGFloat) -> CGFloat {
        let count = CGFloat(max(digits, 1))
        let spacing = CGFloat(max(digits - 1, 0)) * codeBoxSpacing
        for width in [codeBoxWidth, codeBoxCompactWidth] where count * width + spacing <= available {
            return width
        }
        // Even the compact row does not fit: share the band out rather than overflow it.
        return max(12, (available - spacing) / count)
    }

    /// The screens run under a transparent navigation bar (`separatorColor` and `opaqueBackgroundColor`
    /// are both `.clear`, `AuthorizationSequenceController.swift:84`), and the compact code layout pushes
    /// content below it — `insets.top = navigationBarHeight`
    /// (`AuthorizationSequenceCodeEntryControllerNode.swift:655`) — which Doni does on every screen
    /// offering the back chevron: the 100 pt `IntroMessage` sticker that keeps the reference's wide
    /// layout clear is an asset this app does not carry.
    public static let navigationBarHeight: CGFloat = 44
    /// The back button is a 44 pt square at the leading edge; `NavigationBackButtonNode` grows its
    /// touch area the same way (`hitTestSlop`, `NavigationBackButtonNode.swift:57`).
    public static let backButtonSide: CGFloat = 44
}

/// Motion tokens, read off the reference's animation calls. `kCAMediaTimingFunctionSpring` is not one
/// curve: `CAAnimationUtils.swift:119-204` routes a 0.5 s animation through a real `CASpringAnimation`
/// and *every other duration* through the bezier below, so the 0.3 s hand-over is a bezier even though
/// the call site says "spring".
public enum TelegramLoginMotion {
    /// `CAMediaTimingFunction(controlPoints: 0.380, 0.700, 0.125, 1.000)` (`CAAnimationUtils.swift:186`).
    public static let spring = Animation.timingCurve(0.380, 0.700, 0.125, 1.000, duration: 0.3)

    /// `CAMediaTimingFunctionName.easeInEaseOut`, the default of `animateAlpha` and
    /// `animateScale` (`CAAnimationUtils.swift:397`, `:401`).
    public static func easeInOut(_ duration: Double) -> Animation {
        Animation.timingCurve(0.42, 0.0, 0.58, 1.0, duration: duration)
    }

    /// `make26SpringAnimationImpl` (`UIKitUtils.m:68-77`): mass 1, stiffness 555.027, damping
    /// 47.118 — ζ = 47.118 / (2·√555.027) = 1.000, ω₀ = √555.027 = 23.559 rad/s, so critically
    /// damped with a 2π/ω₀ = 0.2667 s response, which is how SwiftUI's `spring(response:)` is fed.
    public static let presentation = Animation.spring(response: 0.2667, dampingFraction: 1.0)

    /// The outgoing text block (title + notice) thrown 140 pt up (`PhoneEntryControllerNode.swift:555`).
    public static let ghostTextOffset: CGFloat = -140
    /// The outgoing field block thrown 100 pt up while it shrinks (`:548`).
    public static let ghostFieldOffset: CGFloat = -100
    /// …to 30 % of its size (`:549`).
    public static let ghostFieldScale: CGFloat = 0.3
    /// Both snapshots fade in 0.2 s (`:544`, `:551`); the field block's scale takes 0.4 s.
    public static let ghostFade = easeInOut(0.2)
    public static let ghostScale = easeInOut(0.4)
    /// The incoming screen's nodes fade in over 0.3 s (`:569`), as does the first screen
    /// when the sequence opens (`AuthorizationSequenceController.swift:1367`).
    public static let fadeIn = easeInOut(0.3)

    /// …and the incoming sticker grows from 30 % of its size through the same 0.3 s
    /// (`Docs/design-tokens.md:261`).
    public static let crestFrom: CGFloat = 0.3

    /// Doni's own: the sequence does not end with a root swap — the last screen lifts off the shell
    /// already under it. The curve is the reference's `presentation` spring (`CAAnimationUtils.swift:119-204`).
    public static let leaveScale: CGFloat = 1.18

    /// Wrong code: the boxes shake. `addShakeAnimation` (`ShakeAnimation.swift:9-39`) builds a keyframe
    /// animation on `position.x`: 0, then `amplitude · sign · 1/(i+1)` for `count` alternating steps,
    /// then 0, keyframes evenly spaced over the duration.
    public static func shakeOffsets(amplitude: CGFloat, count: Int, decay: Bool) -> [CGFloat] {
        var values: [CGFloat] = [0]
        for i in 0..<count {
            let sign: CGFloat = i % 2 == 0 ? 1.0 : -1.0
            let multiplier = decay ? 1.0 / CGFloat(i + 1) : 1.0
            values.append(amplitude * sign * multiplier)
        }
        values.append(0)
        return values
    }

    /// `amplitude: -30, duration: 0.5, count: 6, decay: true` (`AuthorizationSequenceCodeEntryControllerNode.swift:953`).
    public static let codeShake = shakeOffsets(amplitude: -30, count: 6, decay: true)
    public static let codeShakeDuration: Double = 0.5
    /// The word and phrase fields shake with the helper's own defaults (`:919`, `:945`).
    public static let wordShake = shakeOffsets(amplitude: 3, count: 4, decay: false)
    public static let wordShakeDuration: Double = 0.3

    /// An accepted code pulses once: scale 1 → 1.1 → 1 over 0.4 s (`:1003-1004`).
    public static let successPulse: [CGFloat] = [1.0, 1.1, 1.0]
    public static let successPulseDuration: Double = 0.4

    /// A rejected code stays red for 0.85 s before the boxes are emptied (`CodeInputView.swift:193`).
    public static let failedResetDelay: Double = 0.85
    /// Box borders cross-fade their colour over 0.15 s linear (`CodeInputView.swift:72`).
    public static let borderColour = Animation.linear(duration: 0.15)

    /// The error line sits 11 pt under the field, plus 13 more once the screen is wider than 320 pt
    /// (`AuthorizationSequenceCodeEntryControllerNode.swift:967`).
    public static func errorOffset(screenWidth: CGFloat) -> CGFloat {
        screenWidth > 320 ? 24 : 11
    }

    /// A digit entering its box fades over 0.25 s and rises 35 % of the box height on a spring
    /// (`CodeInputView.swift:82-86`): `mass 5, stiffness 900, damping 70` (`UIKitUtils.m:86-90`,
    /// `CAAnimationUtils.swift:338`) — ω₀ = √(900/5) = 13.416 rad/s → response 0.468, ζ = 0.522.
    public static let digitEnter = Animation.spring(response: 0.4683, dampingFraction: 0.5218)
    public static let digitRiseFraction: CGFloat = 0.35
    /// A digit leaving its box is snapshotted, faded over 0.2 s and dropped half a box (`CodeInputView.swift:90-95`).
    public static let digitLeave = easeInOut(0.2)
    public static let digitFallFraction: CGFloat = 0.5

    /// `addShakeAnimation` spaces keyframes evenly, so the offset at progress `t` interpolates linearly
    /// between two neighbours in `offsets`.
    public static func shakeOffset(at t: Double, offsets: [CGFloat]) -> CGFloat {
        guard offsets.count > 1 else { return 0 }
        let position = min(max(t, 0), 1) * Double(offsets.count - 1)
        let index = min(Int(position), offsets.count - 2)
        let fraction = CGFloat(position - Double(index))
        return offsets[index] + (offsets[index + 1] - offsets[index]) * fraction
    }
}
