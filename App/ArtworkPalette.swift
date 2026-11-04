import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import TelegramDesignSystem

/// The colours a screen wears once it is opened on top of a cover.
///
/// MeloX does not tint a fixed dark surface: it averages the artwork, decides from that average's
/// luminance whether the whole interface should be light or dark, and paints the background, the
/// nav bar, the tab bar and the text out of the result (`ArtworkAccentColorProvider.swift:273-291`,
/// `PlaylistDetailView.swift:151`, `:167`, `:293-304`). That is why a bright cover turns the
/// reference's detail screen pale and a dark one turns it near-black, and why every number this
/// type uses lives in `MusicArtworkPalette`.
struct ArtworkDetailPalette: Equatable, Sendable {
    /// The background, in sRGB components 0…1.
    let backgroundRGB: SIMD3<Double>
    /// Whether the interface this palette dresses should read as dark.
    let prefersDarkAppearance: Bool

    /// What a screen wears when there is nothing to read: a flat 0.16 or 0.88 grey
    /// (`ArtworkAccentColorProvider.swift:10-18`).
    static func fallback(prefersDarkAppearance: Bool) -> Self {
        Self(
            backgroundRGB: SIMD3<Double>(repeating: prefersDarkAppearance
                ? MusicArtworkPalette.fallbackDark
                : MusicArtworkPalette.fallbackLight),
            prefersDarkAppearance: prefersDarkAppearance
        )
    }

    var colorScheme: ColorScheme {
        prefersDarkAppearance ? .dark : .light
    }

    var backgroundColor: Color {
        Color(red: backgroundRGB.x, green: backgroundRGB.y, blue: backgroundRGB.z)
    }
}

/// The palette and the picture a backdrop is drawn from, computed together because both read the
/// same downsampled bitmap.
struct ArtworkDetailAssets: Sendable {
    let palette: ArtworkDetailPalette
    /// Already blurred, at the reference's own 160 px, so a screen can scale it to fill without
    /// asking a filter to keep up with scrolling.
    let blurredBackdrop: CGImage?

    static func fallback(prefersDarkAppearance: Bool) -> Self {
        Self(palette: .fallback(prefersDarkAppearance: prefersDarkAppearance), blurredBackdrop: nil)
    }
}

/// A cover's palette, read the way MeloX reads one.
///
/// The reference downloads a 160 px version of the artwork to do it (`:159-173`); this app already
/// holds the decoded bitmap, so the read starts from that and never touches the network. The work
/// is GPU-side and a list is usually scrolling while it happens, hence the actor.
actor ArtworkPaletteProvider {
    static let shared = ArtworkPaletteProvider()

    private nonisolated static let cache = ArtworkPaletteCache()

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The answer for a cover already read, without waiting on the actor. A detail screen seeds its
    /// palette from this at init so the colours are right from the first frame of the zoom
    /// transition instead of arriving 350 ms into it (`PlaylistDetailView.swift:42-53`).
    nonisolated static func cached(forKey key: String) -> ArtworkDetailAssets? {
        cache.assets(forKey: key)
    }

    /// The palette and the blurred backdrop for one cover. `key` names the picture, and a cover the
    /// user replaced is a different key, so nothing here needs invalidating.
    func assets(from source: CGImage?, key: String,
                fallbackPrefersDarkAppearance: Bool) -> ArtworkDetailAssets {
        guard let source else {
            return .fallback(prefersDarkAppearance: fallbackPrefersDarkAppearance)
        }
        if let held = Self.cache.assets(forKey: key) { return held }

        let prepared = downsampled(CIImage(cgImage: source))
        let assets = ArtworkDetailAssets(
            palette: makePalette(from: averageColor(of: prepared)),
            blurredBackdrop: makeBlurredBackdrop(from: prepared)
        )
        Self.cache.insert(assets, forKey: key)
        return assets
    }

    /// To 160 px on the longest side, which is what the reference reads and blurs
    /// (`:175-185`).
    private func downsampled(_ image: CIImage) -> CIImage {
        let maximumDimension = max(image.extent.width, image.extent.height)
        guard maximumDimension > MusicArtworkPalette.sourceMaxSide else { return image }

        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(MusicArtworkPalette.sourceMaxSide / maximumDimension)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }

    /// `:187-204` — clamped at the edges so the blur has something to sample past the border, then
    /// cropped back to the picture's own extent.
    private func makeBlurredBackdrop(from image: CIImage) -> CGImage? {
        let extent = image.extent.integral
        guard !extent.isEmpty, !extent.isInfinite else { return nil }

        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image.clampedToExtent()
        filter.radius = Float(MusicArtworkPalette.blurRadius)
        guard let output = filter.outputImage?.cropped(to: extent) else { return nil }

        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// One `areaAverage` down to a single pixel, read back as bytes (`:206-237`).
    private func averageColor(of image: CIImage) -> SIMD3<Double> {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else {
            return SIMD3<Double>(repeating: MusicArtworkPalette.fallbackLight)
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: colorSpace)
        return SIMD3<Double>(Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    /// `:273-291` — the luminance picks the appearance, and the background is the average pulled
    /// toward black or toward white so text laid over it keeps its contrast either way.
    private func makePalette(from source: SIMD3<Double>) -> ArtworkDetailPalette {
        let prefersDark = relativeLuminance(source) < MusicArtworkPalette.darkLuminanceThreshold
        let background: SIMD3<Double>
        if prefersDark {
            background = source * MusicArtworkPalette.darkMix
                + SIMD3<Double>(repeating: MusicArtworkPalette.darkLift) * (1 - MusicArtworkPalette.darkMix)
        } else {
            background = source * MusicArtworkPalette.lightMix
                + SIMD3<Double>(repeating: MusicArtworkPalette.lightLift) * (1 - MusicArtworkPalette.lightMix)
        }
        return ArtworkDetailPalette(backgroundRGB: clamped(background), prefersDarkAppearance: prefersDark)
    }

    private func relativeLuminance(_ color: SIMD3<Double>) -> Double {
        color.x * MusicArtworkPalette.luminanceRed
            + color.y * MusicArtworkPalette.luminanceGreen
            + color.z * MusicArtworkPalette.luminanceBlue
    }

    private func clamped(_ color: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            min(max(color.x, 0), 1),
            min(max(color.y, 0), 1),
            min(max(color.z, 0), 1)
        )
    }
}

/// The read results, kept by the picture's own name: 80 covers, 12 MB, costed by the blurred
/// bitmap's bytes (`ArtworkAccentColorProvider.swift:45-71`).
private nonisolated final class ArtworkPaletteCache: @unchecked Sendable {
    private final class Box: NSObject {
        let assets: ArtworkDetailAssets

        init(_ assets: ArtworkDetailAssets) {
            self.assets = assets
        }
    }

    private let storage = NSCache<NSString, Box>()

    init() {
        storage.countLimit = MusicArtworkPalette.cacheCount
        storage.totalCostLimit = MusicArtworkPalette.cacheBytes
    }

    func assets(forKey key: String) -> ArtworkDetailAssets? {
        storage.object(forKey: key as NSString)?.assets
    }

    func insert(_ assets: ArtworkDetailAssets, forKey key: String) {
        let cost = assets.blurredBackdrop.map { $0.width * $0.height * 4 } ?? 0
        storage.setObject(Box(assets), forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
