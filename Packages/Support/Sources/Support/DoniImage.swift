import Foundation

/// The one image type this app is allowed to name, on either platform.
///
/// It belongs to the foundation rather than to the app because both the phone's screens and the desktop's
/// reach for a decoded cover, and a package cannot see a type declared in a target above it. Everything
/// else here is the three differences between `UIImage` and `NSImage` that the code actually hits — no
/// more surface than that, because a shim that grows is a second UI framework.

/// The one image type the core is allowed to name.
///
/// `CoverArtwork` decodes, caches and measures a single kind of object, and it does that work for the
/// phone and the desktop alike — so the type has to be named once here rather than in twenty-eight places
/// there. Nothing in this file is clever: it is the two platform types under one spelling, plus the three
/// differences between them that the core actually hits.
#if canImport(UIKit)
    import UIKit

    public typealias DoniImage = UIImage

    extension DoniImage {
        /// `UIImage` already hands back its backing image; naming it anyway is what lets the core ask the
        /// same question on both platforms.
        public var coreImage: CGImage? { cgImage }

        /// JPEG at a given quality. The label is part of `UIImage`'s name and there is no reason to carry
        /// the label across, only the bytes.
        public func encodedJpeg(_ quality: CGFloat) -> Data? {
            jpegData(compressionQuality: quality)
        }
    }
#else
    import AppKit
    import CoreGraphics

    public typealias DoniImage = NSImage

    extension DoniImage {
        /// `NSImage` wants a size with a `CGImage`, and the size worth giving it is the one the image
        /// already has — guessing a point size here would rescale every cover on first draw.
        public convenience init(cgImage: CGImage) {
            self.init(cgImage: cgImage,
                      size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        public var coreImage: CGImage? {
            var rect = NSRect.zero
            return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }

        public func encodedJpeg(_ quality: CGFloat) -> Data? {
            guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }
#endif
