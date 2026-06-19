import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draws a "bubble sheet / scantron" app icon with CoreGraphics.
// Produces two PNGs: a full-bleed version (for .icns) and a transparent
// foreground layer (for Icon Composer's .icon bundle).

let size = 1024.0
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/iconwork"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func makeContext() -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                     bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, to path: String) {
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

// Draw the scantron card + rows of bubbles. `fullBleed` adds the colored tile.
func drawIcon(fullBleed: Bool) -> CGContext {
    let ctx = makeContext()

    if fullBleed {
        // Rounded background tile with a warm-to-cool gradient.
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.2237 // macOS squircle-ish corner
        let path = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let grad = CGGradient(colorsSpace: cs, colors: [color(99, 102, 241), color(20, 184, 166)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    }

    // The answer card: a white sheet, slightly inset.
    let cardInset = fullBleed ? size * 0.17 : size * 0.13
    let cardRect = CGRect(x: cardInset, y: cardInset, width: size - cardInset * 2, height: size - cardInset * 2)
    let cardRadius = size * 0.06
    // Soft shadow under the card (only meaningful on full bleed).
    if fullBleed {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: color(0, 0, 0, 0.28))
    }
    ctx.addPath(CGPath(roundedRect: cardRect, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil))
    ctx.setFillColor(color(250, 250, 248))
    ctx.fillPath()
    if fullBleed { ctx.restoreGState() }

    // Header bar near the top of the card.
    let pad = cardRect.width * 0.12
    let headerHeight = cardRect.height * 0.075
    let headerRect = CGRect(x: cardRect.minX + pad, y: cardRect.maxY - pad - headerHeight,
                            width: cardRect.width - pad * 2, height: headerHeight)
    ctx.addPath(CGPath(roundedRect: headerRect, cornerWidth: headerHeight/2, cornerHeight: headerHeight/2, transform: nil))
    ctx.setFillColor(color(99, 102, 241))
    ctx.fillPath()

    // Rows: a label line + four bubbles, one filled per row.
    let rowCount = 4
    let bubblesPerRow = 4
    let accent = color(20, 184, 166)
    let outline = color(180, 184, 198)
    let labelColor = color(214, 217, 226)

    let topY = headerRect.minY - cardRect.height * 0.10
    let bottomY = cardRect.minY + pad
    let rowSpan = topY - bottomY
    let rowStep = rowSpan / Double(rowCount - 1)
    let bubbleRadius = cardRect.width * 0.052

    // Which bubble is "filled" per row.
    let filled = [1, 3, 0, 2]

    for row in 0..<rowCount {
        let y = topY - Double(row) * rowStep

        // Label line on the left.
        let labelWidth = cardRect.width * 0.20
        let labelHeight = bubbleRadius * 0.85
        let labelRect = CGRect(x: cardRect.minX + pad, y: y - labelHeight/2, width: labelWidth, height: labelHeight)
        ctx.addPath(CGPath(roundedRect: labelRect, cornerWidth: labelHeight/2, cornerHeight: labelHeight/2, transform: nil))
        ctx.setFillColor(labelColor)
        ctx.fillPath()

        // Bubbles on the right.
        let bubbleAreaStart = cardRect.minX + pad + labelWidth + cardRect.width * 0.06
        let bubbleAreaEnd = cardRect.maxX - pad
        let gap = (bubbleAreaEnd - bubbleAreaStart) / Double(bubblesPerRow - 1)

        for b in 0..<bubblesPerRow {
            let cx = bubbleAreaStart + Double(b) * gap
            let circle = CGRect(x: cx - bubbleRadius, y: y - bubbleRadius, width: bubbleRadius * 2, height: bubbleRadius * 2)
            if b == filled[row] {
                ctx.setFillColor(accent)
                ctx.fillEllipse(in: circle)
            } else {
                ctx.setStrokeColor(outline)
                ctx.setLineWidth(bubbleRadius * 0.28)
                ctx.strokeEllipse(in: circle.insetBy(dx: bubbleRadius * 0.14, dy: bubbleRadius * 0.14))
            }
        }
    }

    return ctx
}

save(drawIcon(fullBleed: true), to: "\(outDir)/full-1024.png")
save(drawIcon(fullBleed: false), to: "\(outDir)/layer-foreground-1024.png")
