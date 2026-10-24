import AppKit

struct Geometry {
  static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }
  static func pixelCrop(selection: CGRect, screen: CGRect, image: CGImage) -> CGRect {
    let r = selection.intersection(screen)
    let sx = CGFloat(image.width) / screen.width
    let sy = CGFloat(image.height) / screen.height
    return CGRect(
      x: (r.minX - screen.minX) * sx, y: (screen.maxY - r.maxY) * sy, width: r.width * sx,
      height: r.height * sy)
  }
}
struct DisplayShot {
  let frame: CGRect
  let image: CGImage
}
enum Raster {
  static func compose(_ shots: [DisplayShot], selection: CGRect) -> CGImage? {
    guard selection.width >= 2, selection.height >= 2 else { return nil }
    let scale =
      shots.filter { $0.frame.intersects(selection) }.map {
        CGFloat($0.image.width) / $0.frame.width
      }.max() ?? 1
    guard
      let c = CGContext(
        data: nil, width: Int(ceil(selection.width * scale)),
        height: Int(ceil(selection.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    c.setFillColor(NSColor.black.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: c.width, height: c.height))
    for s in shots {
      let r = selection.intersection(s.frame)
      guard !r.isNull,
        let crop = s.image.cropping(
          to: Geometry.pixelCrop(selection: selection, screen: s.frame, image: s.image))
      else { continue }
      c.draw(
        crop,
        in: CGRect(
          x: (r.minX - selection.minX) * scale, y: (r.minY - selection.minY) * scale,
          width: r.width * scale, height: r.height * scale))
    }
    return c.makeImage()
  }
  static func png(_ image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
}
enum Tool: String, CaseIterable {
  case arrow = "Arrow"
  case box = "Box"
  case text = "Text"
  case cover = "Cover"
}
struct Mark {
  var tool: Tool
  var start: CGPoint
  var end: CGPoint
  var text: String = ""
}
final class Canvas: NSView {
  let image: CGImage
  var marks: [Mark] = []
  var tool: Tool = .arrow
  var pending: Mark?
  var changed: (() -> Void)?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  init(image: CGImage) {
    self.image = image
    super.init(frame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  }
  required init?(coder: NSCoder) { fatalError() }
  func point(_ event: NSEvent) -> CGPoint {
    let p = convert(event.locationInWindow, from: nil)
    return CGPoint(x: max(0, min(bounds.width, p.x)), y: max(0, min(bounds.height, p.y)))
  }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let p = point(event)
    if tool == .text {
      let a = NSAlert()
      a.messageText = "Add text"
      let f = NSTextField(frame: CGRect(x: 0, y: 0, width: 300, height: 28))
      a.accessoryView = f
      a.addButton(withTitle: "Add")
      a.addButton(withTitle: "Cancel")
      a.window.initialFirstResponder = f
      if a.runModal() == .alertFirstButtonReturn && !f.stringValue.isEmpty {
        marks.append(Mark(tool: .text, start: p, end: p, text: f.stringValue))
        changed?()
        needsDisplay = true
      }
    } else {
      pending = Mark(tool: tool, start: p, end: p)
    }
  }
  override func mouseDragged(with event: NSEvent) {
    pending?.end = point(event)
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    if var m = pending {
      m.end = point(event)
      if hypot(m.end.x - m.start.x, m.end.y - m.start.y) > 2 {
        marks.append(m)
        changed?()
      }
    }
    pending = nil
    needsDisplay = true
  }
  func undoMark() {
    if !marks.isEmpty {
      marks.removeLast()
      changed?()
      needsDisplay = true
    }
  }
  func paint(_ c: CGContext, preview: Bool) {
    c.saveGState()
    c.translateBy(x: 0, y: CGFloat(image.height))
    c.scaleBy(x: 1, y: -1)
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    c.restoreGState()
    for m in marks + (preview ? pending.map { [$0] } ?? [] : []) {
      c.saveGState()
      c.setStrokeColor(NSColor.systemOrange.cgColor)
      c.setFillColor(NSColor.systemOrange.cgColor)
      c.setLineWidth(max(3, CGFloat(image.width) / 350))
      c.setLineCap(.round)
      let r = Geometry.rect(m.start, m.end)
      switch m.tool {
      case .cover:
        c.setFillColor(NSColor.black.cgColor)
        c.fill(r)
      case .box: c.stroke(r)
      case .arrow:
        c.move(to: m.start)
        c.addLine(to: m.end)
        c.strokePath()
        let a = atan2(m.end.y - m.start.y, m.end.x - m.start.x)
        let n: CGFloat = 16
        c.move(to: CGPoint(x: m.end.x - n * cos(a - 0.5), y: m.end.y - n * sin(a - 0.5)))
        c.addLine(to: m.end)
        c.addLine(to: CGPoint(x: m.end.x - n * cos(a + 0.5), y: m.end.y - n * sin(a + 0.5)))
        c.strokePath()
      case .text:
        let ns = NSGraphicsContext(cgContext: c, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        (m.text as NSString).draw(
          at: m.start,
          withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 24), .foregroundColor: NSColor.systemOrange,
            .backgroundColor: NSColor.black.withAlphaComponent(0.8),
          ])
        NSGraphicsContext.restoreGraphicsState()
      }
      c.restoreGState()
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let c = NSGraphicsContext.current?.cgContext else { return }
    c.saveGState()
    c.scaleBy(x: bounds.width / CGFloat(image.width), y: bounds.height / CGFloat(image.height))
    paint(c, preview: true)
    c.restoreGState()
  }
  func flattened() -> CGImage? {
    guard
      let c = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    c.translateBy(x: 0, y: CGFloat(image.height))
    c.scaleBy(x: 1, y: -1)
    paint(c, preview: false)
    return c.makeImage()
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
      undoMark()
    } else {
      super.keyDown(with: event)
    }
  }
}
