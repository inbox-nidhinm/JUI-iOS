// Turns a rendered icon (rounded tile, transparent corners) into what iOS
// wants: a full-bleed, opaque square. The corners are filled with the tile's
// own background colour; iOS applies its own rounding on the home screen.
//
//   swift Art/AppIcons/flatten.swift in.png out.png F7C82D
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4, let hex = UInt32(args[3], radix: 16),
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("usage: flatten in.png out.png RRGGBB"); exit(1)
}
let side = image.width
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha channel at all: iOS rejects icons that have one.
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(colorSpace: space, components: [
    CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
    CGFloat(hex & 0xFF) / 255, 1])!)
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
let out = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(out) else { print("write failed"); exit(1) }
