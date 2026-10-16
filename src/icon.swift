// Draws the 1024px app icon: frosted gradient squircle with three course columns.
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(colors: [NSColor(srgbRed: 0.29, green: 0.64, blue: 1, alpha: 1),
                    NSColor(srgbRed: 0.48, green: 0.36, blue: 1, alpha: 1)])!
    .draw(in: shape, angle: -60)

// three columns of decreasing height, hanging from the top
let colW: CGFloat = 150, gap: CGFloat = 46
let heights: [CGFloat] = [500, 370, 240]
let total = 3 * colW + 2 * gap
var x = (size - total) / 2
let top = size - 270
for (i, h) in heights.enumerated() {
    let r = NSRect(x: x, y: top - h, width: colW, height: h)
    NSColor.white.withAlphaComponent(i == 0 ? 0.98 : 0.82 - CGFloat(i) * 0.12).setFill()
    NSBezierPath(roundedRect: r, xRadius: 44, yRadius: 44).fill()
    x += colW + gap
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
