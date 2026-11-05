#!/usr/bin/env swift
// Regenerates the README's logo: the app icon with its corners made transparent.
//
// GitHub markdown has no way to round an image — no CSS, no attribute — so a square tile is what a
// reader sees, and it does not match the icon they get on the springboard. The radius is the 22.5 %
// of the side that iOS itself masks with, which is also what `DoniLogo` clips to, so all three are
// one shape.
//
//   swift Scripts/round-icon.swift App/Assets.xcassets/AppIcon.appiconset/icon-1024.png Docs/doni-icon.png
//
// Clipping happens in a bitmap context rather than through AppKit because AppKit clips without
// antialiasing and the edge comes out stepped.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write("round-icon: usage: round-icon.swift <in.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

let side = image.width
let corner = CGFloat(side) * 0.225
guard let context = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write("round-icon: cannot open a bitmap context\n".data(using: .utf8)!)
    exit(1)
}

context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                       cornerWidth: corner,
                       cornerHeight: corner,
                       transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

guard let rounded = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                        UTType.png.identifier as CFString,
                                                        1,
                                                        nil)
else {
    FileHandle.standardError.write("round-icon: cannot encode a PNG\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(destination, rounded, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("round-icon: cannot write \(args[2])\n".data(using: .utf8)!)
    exit(1)
}
print("round-icon: \(side) px, corner \(Int(corner)) px → \(args[2])")
