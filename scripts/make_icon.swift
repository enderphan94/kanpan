// Renders the Kanpan app icon (a checklist on a blue→indigo squircle) to a
// 1024×1024 PNG using only CoreGraphics + ImageIO — no design assets needed.
// Usage: swift scripts/make_icon.swift <output.png>
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("failed to create context\n", stderr); exit(1)
}

let full = CGRect(x: 0, y: 0, width: size, height: size)
let rect = full.insetBy(dx: 64, dy: 64)
let radius = rect.width * 0.225

// Squircle background with diagonal gradient.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let colors = [CGColor(red: 0.30, green: 0.55, blue: 0.98, alpha: 1),
              CGColor(red: 0.42, green: 0.40, blue: 0.92, alpha: 1)] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// Three checklist rows (top two checked).
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.setStrokeColor(white)
ctx.setFillColor(white)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let rowH = rect.height * 0.150
let gap = rect.height * 0.090
let leftX = rect.minX + rect.width * 0.20
let boxSize = rowH
let lineX = leftX + boxSize * 1.55
let lineW = rect.width * 0.40
let topY = rect.midY + (rowH + gap)

for i in 0..<3 {
    let y = topY - CGFloat(i) * (rowH + gap)
    let box = CGRect(x: leftX, y: y - boxSize / 2, width: boxSize, height: boxSize)

    ctx.setLineWidth(boxSize * 0.12)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: boxSize * 0.26,
                       cornerHeight: boxSize * 0.26, transform: nil))
    ctx.strokePath()

    if i < 2 {
        ctx.setLineWidth(boxSize * 0.13)
        ctx.move(to: CGPoint(x: box.minX + box.width * 0.24, y: box.minY + box.height * 0.50))
        ctx.addLine(to: CGPoint(x: box.minX + box.width * 0.44, y: box.minY + box.height * 0.28))
        ctx.addLine(to: CGPoint(x: box.minX + box.width * 0.78, y: box.minY + box.height * 0.72))
        ctx.strokePath()
    }

    let line = CGRect(x: lineX, y: y - boxSize * 0.16, width: lineW, height: boxSize * 0.32)
    ctx.setAlpha(i < 2 ? 0.96 : 0.55)
    ctx.addPath(CGPath(roundedRect: line, cornerWidth: boxSize * 0.16,
                       cornerHeight: boxSize * 0.16, transform: nil))
    ctx.fillPath()
    ctx.setAlpha(1)
}

guard let img = ctx.makeImage() else { fputs("no image\n", stderr); exit(1) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("no dest\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, img, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(outPath)")
} else {
    fputs("write failed\n", stderr); exit(1)
}
