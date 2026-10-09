import AppKit

// Original vector artwork. Draw at each output size for crisp small icons.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func draw(size: Int, filename: String) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1_024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1), ending: NSColor(calibratedWhite: 0.06, alpha: 1))!.draw(in: background, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    background.lineWidth = 3
    background.stroke()
    NSColor.black.setFill()
    let notch = NSBezierPath(roundedRect: NSRect(x: 345, y: 800, width: 334, height: 230), xRadius: 48, yRadius: 48)
    notch.fill()
    let gold = NSColor(calibratedRed: 0.89, green: 0.71, blue: 0.43, alpha: 1)
    let left = NSBezierPath()
    left.move(to: NSPoint(x: 512, y: 298))
    left.curve(to: NSPoint(x: 239, y: 338), controlPoint1: NSPoint(x: 399, y: 364), controlPoint2: NSPoint(x: 329, y: 359))
    left.line(to: NSPoint(x: 239, y: 634))
    left.curve(to: NSPoint(x: 512, y: 594), controlPoint1: NSPoint(x: 333, y: 671), controlPoint2: NSPoint(x: 428, y: 655))
    left.close()
    NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.85, alpha: 1).setFill()
    left.fill()
    let right = NSBezierPath()
    right.move(to: NSPoint(x: 536, y: 298))
    right.curve(to: NSPoint(x: 809, y: 338), controlPoint1: NSPoint(x: 649, y: 364), controlPoint2: NSPoint(x: 719, y: 359))
    right.line(to: NSPoint(x: 809, y: 634))
    right.curve(to: NSPoint(x: 536, y: 594), controlPoint1: NSPoint(x: 715, y: 671), controlPoint2: NSPoint(x: 620, y: 655))
    right.close()
    gold.setFill()
    right.fill()
    for (x, startY) in [(CGFloat(285), CGFloat(564)), (CGFloat(581), CGFloat(529))] {
        for row in 0..<3 {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: startY - CGFloat(row) * 58))
            line.line(to: NSPoint(x: x + 172, y: startY - CGFloat(row) * 58 - 13))
            line.lineWidth = 11
            line.lineCapStyle = .round
            NSColor(calibratedWhite: 0.13, alpha: 0.25).setStroke()
            line.stroke()
        }
    }
    gold.setFill()
    NSBezierPath(roundedRect: NSRect(x: 461, y: 235, width: 126, height: 9), xRadius: 4, yRadius: 4).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
    try png.write(to: destination.appendingPathComponent(filename))
}
for size in [16, 32, 128, 256, 512] {
    try draw(size: size, filename: "icon_\(size)x\(size).png")
    try draw(size: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
