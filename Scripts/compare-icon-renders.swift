// Icon source calibration comparator (CoreGraphics only — no third-party
// dependencies).
//
// Usage: compare-icon-renders <render.png> <preview.png> [--light]
//
// Default (dark) mode: requires BYTE-identical files (the calibration
// contract for Assets/AppIcon.icon against AppIconDarkPreview.png).
//
// --light mode: requires EXACT alpha/Squircle geometry (zero differing
// alpha bytes) and a strict bounded RGB tolerance (mean per-pixel
// max-channel error <= 1.5/255, at most 8 pixels above 32/255). Both
// images are drawn into the same RGBA8 space first, so the PNG bit depth
// and color profile cannot produce a false comparison.
//
// Exit status: 0 ok, 1 mismatch (details on stderr), 2 usage/IO error.
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: compare-icon-renders <render.png> <preview.png> [--light]\n".data(using: .utf8)!)
    exit(2)
}
let lightMode = args.contains("--light")
let renderPath = args[1]
let previewPath = args[2]

func data(_ path: String) -> Data? { try? Data(contentsOf: URL(fileURLWithPath: path)) }

guard let renderData = data(renderPath), let previewData = data(previewPath) else {
    FileHandle.standardError.write("FAIL: cannot read input images\n".data(using: .utf8)!)
    exit(2)
}

/// Raw RGBA8 pixels via CoreGraphics (depth/profile independent).
func rgba(_ data: Data) -> (w: Int, h: Int, bytes: [UInt8])? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ok = buf.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress,
              let ctx = CGContext(data: base, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? (w, h, buf) : nil
}

if !lightMode {
    if renderData == previewData {
        print("ok:   Dark render is byte-identical to the preview")
        exit(0)
    }
    let a = sha256Hex(renderData), b = sha256Hex(previewData)
    FileHandle.standardError.write("FAIL: Dark render differs from the preview (\(a) != \(b))\n".data(using: .utf8)!)
    exit(1)
}

guard let a = rgba(renderData), let b = rgba(previewData) else {
    FileHandle.standardError.write("FAIL: cannot decode one of the Light images\n".data(using: .utf8)!)
    exit(2)
}
guard a.w == b.w, a.h == b.h else {
    FileHandle.standardError.write("FAIL: Light size \(a.w)x\(a.h) != preview \(b.w)x\(b.h)\n".data(using: .utf8)!)
    exit(1)
}

var alphaDiff = 0
var total = 0
var pixels = 0
var over32 = 0
var maxErr = 0
for i in stride(from: 0, to: a.bytes.count, by: 4) {
    if a.bytes[i + 3] != b.bytes[i + 3] { alphaDiff += 1 }
    var e = 0
    for c in 0..<3 {
        e = max(e, abs(Int(a.bytes[i + c]) - Int(b.bytes[i + c])))
    }
    total += e
    pixels += 1
    if e > maxErr { maxErr = e }
    if e > 32 { over32 += 1 }
}
let mean = Double(total) / Double(pixels)
print(String(format: "info: Light alpha differing pixels: %d", alphaDiff))
print(String(format: "info: Light mean max-channel RGB error: %.3f; max: %d; pixels > 32: %d",
             mean, maxErr, over32))

var failed = false
if alphaDiff != 0 {
    FileHandle.standardError.write("FAIL: Light alpha/Squircle geometry differs in \(alphaDiff) pixels\n".data(using: .utf8)!)
    failed = true
}
if mean > 1.5 {
    FileHandle.standardError.write(String(format: "FAIL: Light mean RGB error %.3f exceeds the 1.5 ceiling\n", mean).data(using: .utf8)!)
    failed = true
}
if over32 > 8 {
    FileHandle.standardError.write("FAIL: Light RGB error above 32 in \(over32) pixels (limit 8)\n".data(using: .utf8)!)
    failed = true
}
if failed { exit(1) }
print("ok:   Light render keeps the Dark alpha geometry and bounded RGB tolerance")
exit(0)

func sha256Hex(_ d: Data) -> String {
    // Compact SHA-256 (no CryptoKit dependency so plain CLT works).
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                       0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
    var msg = [UInt8](d)
    let bitLen = UInt64(msg.count) * 8
    msg.append(0x80)
    while msg.count % 64 != 56 { msg.append(0) }
    for i in (0..<8).reversed() { msg.append(UInt8((bitLen >> (8 * UInt64(i))) & 0xff)) }
    for chunk in stride(from: 0, to: msg.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let o = chunk + i * 4
            w[i] = (UInt32(msg[o]) << 24) | (UInt32(msg[o + 1]) << 16)
                | (UInt32(msg[o + 2]) << 8) | UInt32(msg[o + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var (a1, b1, c1, d1, e1, f1, g1, h1) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let S1 = rotr(e1, 6) ^ rotr(e1, 11) ^ rotr(e1, 25)
            let ch = (e1 & f1) ^ (~e1 & g1)
            let t1 = h1 &+ S1 &+ ch &+ k[i] &+ w[i]
            let S0 = rotr(a1, 2) ^ rotr(a1, 13) ^ rotr(a1, 22)
            let maj = (a1 & b1) ^ (a1 & c1) ^ (b1 & c1)
            let t2 = S0 &+ maj
            h1 = g1; g1 = f1; f1 = e1; e1 = d1 &+ t1
            d1 = c1; c1 = b1; b1 = a1; a1 = t1 &+ t2
        }
        h[0] = h[0] &+ a1; h[1] = h[1] &+ b1; h[2] = h[2] &+ c1; h[3] = h[3] &+ d1
        h[4] = h[4] &+ e1; h[5] = h[5] &+ f1; h[6] = h[6] &+ g1; h[7] = h[7] &+ h1
    }
    return h.map { String(format: "%08x", $0) }.joined()
}

func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
