import SwiftUI

public extension Image {
    /// A decoded cover, from whichever image type this platform reads.
    ///
    /// SwiftUI spells the same initializer `uiImage:` on the phone and `nsImage:` on the desktop, which
    /// is a label difference and nothing else — so it belongs in one place rather than in every view
    /// that shows a picture.
    init(doni image: DoniImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}
