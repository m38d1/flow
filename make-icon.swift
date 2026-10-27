import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let tileRect = NSRect(x: 84, y: 84, width: 856, height: 856)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 198, yRadius: 198)
NSGradient(colors: [color(0x2F6BFF), color(0x0AC2A0)])!.draw(in: tile, angle: -52)

tile.lineWidth = 6
color(0xFFFFFF, 0.12).setStroke()
tile.stroke()

func wave(startY: CGFloat, crest: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = 76
    path.lineCapStyle = .round
    path.move(to: NSPoint(x: 244, y: startY))
    path.curve(
        to: NSPoint(x: 512, y: startY),
        controlPoint1: NSPoint(x: 334, y: startY + crest),
        controlPoint2: NSPoint(x: 422, y: startY + crest)
    )
    path.curve(
        to: NSPoint(x: 780, y: startY),
        controlPoint1: NSPoint(x: 602, y: startY - crest),
        controlPoint2: NSPoint(x: 690, y: startY - crest)
    )
    return path
}

let upper = wave(startY: 596, crest: 118)
let lower = wave(startY: 428, crest: -118)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()

NSColor.white.withAlphaComponent(0.98).setStroke()
upper.stroke()
NSColor.white.withAlphaComponent(0.92).setStroke()
lower.stroke()

NSShadow().set()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not render icon")
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
try png.write(to: output)
print("wrote \(output.path)")
