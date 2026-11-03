import Foundation
import CoreGraphics
import ImageIO
import AppKit

// A pixel probe: the screenshots are the spec, so the numbers come off them rather than off a guess.
// Usage:
//   probe <png> rows            -> horizontal edge candidates (rows where the mean brightness jumps)
//   probe <png> col <x>         -> colour samples down column x
//   probe <png> row <y>         -> colour samples along row y
//   probe <png> box <x> <y> <w> <h> -> dominant colours inside a box
//   probe <png> size

let args = CommandLine.arguments
guard args.count >= 2,
      let image = NSImage(contentsOfFile: args[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("cannot load \(args[1])"); exit(1)
}

let w = cg.width, h = cg.height
let bytesPerPixel = 4
let bytesPerRow = bytesPerPixel * w
var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let i = y * bytesPerRow + x * bytesPerPixel
    return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
}
func hex(_ x: Int, _ y: Int) -> String {
    let p = pixel(x, y)
    return String(format: "#%02x%02x%02x", p.r, p.g, p.b)
}
func lum(_ x: Int, _ y: Int) -> Double {
    let p = pixel(x, y)
    return (0.299 * Double(p.r) + 0.587 * Double(p.g) + 0.114 * Double(p.b)) / 255.0
}

let cmd = args.count > 2 ? args[2] : "size"
switch cmd {
case "size":
    print("pixels \(w) x \(h)  points \(Double(w) / 3.0) x \(Double(h) / 3.0) @3x")
case "rows":
    // A separator is a run of one row that is brighter than both neighbours across the text column.
    let x0 = Int(Double(w) * 0.30), x1 = Int(Double(w) * 0.95)
    var previous = 0.0
    for y in 0..<h {
        var sum = 0.0
        var x = x0
        while x < x1 { sum += lum(x, y); x += 3 }
        let mean = sum / Double((x1 - x0) / 3)
        if mean - previous > 0.035, mean > 0.06 {
            print(String(format: "y=%d  pt=%.1f  mean=%.3f  jump=+%.3f  mid=%@",
                         y, Double(y) / 3.0, mean, mean - previous, hex(x0 + 40, y)))
        }
        previous = mean
    }
case "col":
    let x = Int(args[3])!
    var step = args.count > 4 ? Int(args[4])! : 3
    if step < 1 { step = 1 }
    var y = 0
    while y < h {
        print(String(format: "y=%4d pt=%6.1f %@", y, Double(y) / 3.0, hex(x, y)))
        y += step
    }
case "row":
    let y = Int(args[3])!
    var step = args.count > 4 ? Int(args[4])! : 3
    if step < 1 { step = 1 }
    var x = 0
    while x < w {
        print(String(format: "x=%4d pt=%6.1f %@", x, Double(x) / 3.0, hex(x, y)))
        x += step
    }
case "box":
    let x = Int(args[3])!, y = Int(args[4])!, bw = Int(args[5])!, bh = Int(args[6])!
    var counts: [String: Int] = [:]
    for yy in y..<(y + bh) {
        for xx in x..<(x + bw) { counts[hex(xx, yy), default: 0] += 1 }
    }
    for entry in counts.sorted(by: { $0.value > $1.value }).prefix(12) {
        print(String(format: "%@  %d px  %.1f%%", entry.key, entry.value,
                     Double(entry.value) * 100.0 / Double(bw * bh)))
    }
case "vedges":
    // Vertical scan at one column: every row where the brightness steps by more than the
    // threshold. This is how a row boundary, an avatar's edge or a capsule's rim is found.
    let x = Int(args[3])!, y0 = Int(args[4])!, y1 = Int(args[5])!
    let threshold = args.count > 6 ? Double(args[6])! : 0.05
    var previous = lum(x, y0)
    var y = y0 + 1
    while y < y1 {
        let value = lum(x, y)
        if abs(value - previous) >= threshold {
            print(String(format: "y=%4d pt=%6.1f  Δ%+.3f  %@ → %@", y, Double(y) / 3.0,
                         value - previous, hex(x, y - 1), hex(x, y)))
        }
        previous = value
        y += 1
    }
case "hedges":
    let y = Int(args[3])!, x0 = Int(args[4])!, x1 = Int(args[5])!
    let threshold = args.count > 6 ? Double(args[6])! : 0.05
    var previous = lum(x0, y)
    var x = x0 + 1
    while x < x1 {
        let value = lum(x, y)
        if abs(value - previous) >= threshold {
            print(String(format: "x=%4d pt=%6.1f  Δ%+.3f  %@ → %@", x, Double(x) / 3.0,
                         value - previous, hex(x - 1, y), hex(x, y)))
        }
        previous = value
        x += 1
    }
case "bands":
    // Where the text is: for each row of pixels, how many of them carry a glyph. Runs of glyph rows
    // are the lines of text, and the gaps between runs are the row boundaries.
    let x0 = Int(args[3])!, x1 = Int(args[4])!, y0 = Int(args[5])!, y1 = Int(args[6])!
    let threshold = args.count > 7 ? Double(args[7])! : 0.35
    var run: [Int] = []
    var inRun = false
    var y = y0
    while y < y1 {
        var hits = 0
        var x = x0
        while x < x1 { if lum(x, y) > threshold { hits += 1 }; x += 1 }
        let has = hits > 6
        if has, !inRun { run = [y, y]; inRun = true }
        if has, inRun { run[1] = y }
        if !has, inRun {
            print(String(format: "text band y=%4d..%4d  pt=%.1f..%.1f  height=%.1f pt  centre=%.1f pt",
                         run[0], run[1], Double(run[0]) / 3.0, Double(run[1]) / 3.0,
                         Double(run[1] - run[0] + 1) / 3.0, Double(run[0] + run[1]) / 6.0))
            inRun = false
        }
        y += 1
    }
default:
    print("unknown command \(cmd)")
}
