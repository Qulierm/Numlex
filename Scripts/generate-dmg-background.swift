#!/usr/bin/env swift
// Generate the styled DMG Finder background for Numlex.
//
// Uses only built-in macOS frameworks (CoreGraphics + AppKit + ImageIO).
// No external dependencies. Deterministic: the same inputs produce the
// same pixels and the same file bytes.
//
// Canvas: 800x450 pt (the Finder content area). Emits sRGB, 8-bpc, alpha
// PNGs explicitly tagged sRGB (via a standards-based "sRGB" chunk):
//   <out-1x>  800x450  px
//   <out-2x>  1600x900 px — Retina; the 1x tagline PNG is upscaled with
//              high-quality interpolation, all vector art re-rendered at 2x.
//
// Layout (points, origin top-left of the 800x450 content area):
//   background : near-black -> deep blue vertical gradient (#090B11 -> #111623)
//   glow app   : radial purple (#8B5CF6 @20%) centered at (220, 285), radius 200
//   glow apps  : radial blue   (#3B82F6 @20%) centered at (580, 285), radius 200
//   tagline    : numlex-tagline.png (506x122 px @1x) centered horizontally,
//                top edge at y=56
//   arrow      : thin (2.2 pt) purple->blue shaft x=312..452 at y=285,
//                solid blue head tip at x=488
//   footer     : "Drag Numlex to Applications to install"
//                SF system 15 pt medium, #7C838E, centered, block top y=416
//
// Usage: generate-dmg-background.swift <tagline-png> <out-1x.png> <out-2x.png>

import AppKit
import CoreGraphics
import ImageIO

func die(_ m: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + m + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    die("usage: generate-dmg-background.swift <tagline-png> <out-1x.png> <out-2x.png>")
}
let taglinePath = args[1]
let out1x = args[2]
let out2x = args[3]

guard let tagNSImage = NSImage(contentsOfFile: taglinePath),
      let tagSrc = tagNSImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { die("cannot load tagline PNG: \(taglinePath)") }

// Canvas geometry (points). A uniform `scale` factor produces the 2x output.
let CW: CGFloat = 800
let CH: CGFloat = 450
let iconCenterY: CGFloat = 285      // top-down
let appX: CGFloat = 220
let appsX: CGFloat = 580
let glowRadius: CGFloat = 200
let taglineW: CGFloat = 506
let taglineH: CGFloat = 122
let taglineTop: CGFloat = 56        // top-down
let arrowY: CGFloat = iconCenterY   // top-down
let arrowX0: CGFloat = 312
let arrowX1: CGFloat = 452
let arrowHeadTip: CGFloat = 488
let arrowHeadHalf: CGFloat = 7
let footerBlockTop: CGFloat = 416   // top-down
let footerText = "Drag Numlex to Applications to install"

// sRGB colors.
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let gradTop = rgb(9, 11, 17)
let gradBottom = rgb(17, 22, 35)
let glowPurple = rgb(139, 92, 246)   // numlex purple accent
let glowBlue = rgb(59, 130, 246)     // numlex blue accent
let footerGray = rgb(124, 131, 142)  // #7C838E

// Top-down y -> bottom-up CG y.
func cy(_ topDown: CGFloat) -> CGFloat { CH - topDown }

func render(scale: CGFloat) -> CGImage {
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { die("no sRGB color space") }
    let w = Int(CW * scale)
    let h = Int(CH * scale)
    guard let cg = CGContext(data: nil, width: w, height: h,
                             bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { die("cannot create \(w)x\(h) CGContext") }
    cg.scaleBy(x: scale, y: scale)
    cg.interpolationQuality = CGInterpolationQuality.high
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    let nsctx = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.current = nsctx

    // 1) Background gradient (top -> bottom).
    NSGradient(starting: gradTop, ending: gradBottom)?
        .draw(in: CGRect(x: 0, y: 0, width: CW, height: CH), angle: -90)

    // 2) Radial glows behind the two icon positions.
    func radialGlow(centerX x: CGFloat, color: NSColor) {
        let center = CGPoint(x: x, y: cy(iconCenterY))
        let inner = NSColor(srgbRed: color.redComponent, green: color.greenComponent,
                            blue: color.blueComponent, alpha: 0.20)
        let outer = NSColor(srgbRed: color.redComponent, green: color.greenComponent,
                            blue: color.blueComponent, alpha: 0.0)
        NSGradient(colors: [inner, outer])?
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: glowRadius, options: [])
    }
    radialGlow(centerX: appX, color: glowPurple)
    radialGlow(centerX: appsX, color: glowBlue)

    // 3) Tagline (supplied transparent PNG), centered; high-quality upscale at 2x.
    let tagRect = CGRect(x: (CW - taglineW) / 2, y: cy(taglineTop + taglineH),
                         width: taglineW, height: taglineH)
    cg.draw(tagSrc, in: tagRect)

    // 4) Thin elegant arrow between the icon slots (y values top-down, flipped via cy()).
    let shaftRect = CGRect(x: arrowX0, y: cy(arrowY) - 1.1,
                           width: arrowX1 - arrowX0, height: 2.2)
    let shaftBezier = NSBezierPath(roundedRect: shaftRect, xRadius: 1.1, yRadius: 1.1)
    NSGradient(colors: [glowPurple, glowBlue])?.draw(in: shaftBezier, angle: 0)
    let headBezier = NSBezierPath()
    headBezier.move(to: NSPoint(x: arrowX1 - 2, y: cy(arrowY) - arrowHeadHalf))
    headBezier.line(to: NSPoint(x: arrowHeadTip, y: cy(arrowY)))
    headBezier.line(to: NSPoint(x: arrowX1 - 2, y: cy(arrowY) + arrowHeadHalf))
    headBezier.close()
    glowBlue.withAlphaComponent(0.95).setFill()
    headBezier.fill()

    // 5) Footer line, centered, block top at footerBlockTop (top-down).
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let astr = NSAttributedString(string: footerText, attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: footerGray,
        .paragraphStyle: para,
    ])
    let tsize = astr.size()
    astr.draw(in: CGRect(x: 0, y: cy(footerBlockTop), width: CW, height: tsize.height))

    guard let image = cg.makeImage() else { die("CGContext.makeImage failed") }
    return image
}

// CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320) as used by PNG.
func crc32(_ bytes: [UInt8]) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        table[i] = c
    }
    var crc: UInt32 = 0xFFFFFFFF
    for b in bytes {
        crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFFFFFF
}

func savePNG(_ image: CGImage, to path: String) {
    let out = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: out)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { die("cannot create PNG destination \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { die("PNG finalize failed for \(path)") }

    // This Swift toolchain does not expose the ImageIO profile property, so
    // tag the PNG as sRGB per the PNG spec: insert an "sRGB" chunk (rendering
    // intent 0 = perceptual) right after IHDR. All pixel values are already
    // sRGB (sRGB CG context + sRGB NSColors).
    guard var png = try? Data(contentsOf: url) else { die("cannot re-read \(path)") }
    let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard png.count > 33, Array(png.prefix(8)) == sig else { die("\(path) is not a PNG") }
    guard Array(png[12 ..< 16]) == Array("IHDR".utf8) else { die("\(path) has no IHDR chunk") }
    // Only tag when the encoder did not already emit an "sRGB" chunk.
    var pos = 8
    var hasSrgb = false
    while pos + 12 <= png.count {
        let b0 = Int(png[pos])
        let b1 = Int(png[pos + 1])
        let b2 = Int(png[pos + 2])
        let b3 = Int(png[pos + 3])
        let ln = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        let ctype = png[pos + 4 ... pos + 7]
        if Array(ctype) == Array("sRGB".utf8) { hasSrgb = true; break }
        if Array(ctype) == Array("IEND".utf8) { break }
        pos += 12 + ln
    }
    if !hasSrgb {
        let srgbTypeData: [UInt8] = [0x73, 0x52, 0x47, 0x42, 0x00]   // "sRGB" + intent
        let crc = crc32(srgbTypeData)
        let crcBytes: [UInt8] = [UInt8((crc >> 24) & 0xFF), UInt8((crc >> 16) & 0xFF),
                                 UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
        let srgbChunk: [UInt8] = [0x00, 0x00, 0x00, 0x01] + srgbTypeData + crcBytes
        let ihdrEnd = 8 + 4 + 4 + 13 + 4   // sig + IHDR(len+type+data+crc)
        png.insert(contentsOf: srgbChunk, at: ihdrEnd)
        do { try png.write(to: url) } catch { die("sRGB chunk write failed for \(path): \(error)") }
    }
}

savePNG(render(scale: 1), to: out1x)
savePNG(render(scale: 2), to: out2x)
print("wrote \(out1x) (800x450) and \(out2x) (1600x900)")
