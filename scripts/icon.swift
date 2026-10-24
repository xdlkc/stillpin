import AppKit

let directory = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = CGFloat(size) / 1024
  let transform = NSAffineTransform()
  transform.scale(by: s)
  transform.concat()
  NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.21, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 20, y: 20, width: 984, height: 984), xRadius: 220, yRadius: 220
  ).fill()
  NSColor(calibratedRed: 0.2, green: 0.85, blue: 0.72, alpha: 1).setStroke()
  let frame = NSBezierPath(
    roundedRect: NSRect(x: 230, y: 270, width: 570, height: 500), xRadius: 65, yRadius: 65)
  frame.lineWidth = 52
  frame.stroke()
  NSColor.white.setStroke()
  let pin = NSBezierPath()
  pin.lineWidth = 50
  pin.lineCapStyle = .round
  pin.move(to: NSPoint(x: 370, y: 380))
  pin.line(to: NSPoint(x: 650, y: 660))
  pin.move(to: NSPoint(x: 520, y: 700))
  pin.line(to: NSPoint(x: 690, y: 530))
  pin.stroke()
  NSGraphicsContext.restoreGraphicsState()
  let data = rep.representation(using: .png, properties: [:])!
  let names: [String]
  switch size {
  case 16: names = ["icon_16x16"]
  case 32: names = ["icon_16x16@2x", "icon_32x32"]
  case 64: names = ["icon_32x32@2x"]
  case 128: names = ["icon_128x128"]
  case 256: names = ["icon_128x128@2x", "icon_256x256"]
  case 512: names = ["icon_256x256@2x", "icon_512x512"]
  default: names = ["icon_512x512@2x"]
  }
  for name in names {
    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }
}
