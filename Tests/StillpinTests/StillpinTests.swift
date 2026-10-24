import AppKit
import Carbon
import XCTest

@testable import Stillpin

final class StillpinTests: XCTestCase {
  func image(_ width: Int = 200, _ height: Int = 100, _ color: NSColor = .white) -> CGImage {
    let c = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(color.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return c.makeImage()!
  }
  func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
    let c = CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let p = c.data!.assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: p, count: 4))
  }
  func testRetinaCropWithNegativeOrigin() {
    let r = Geometry.pixelCrop(
      selection: CGRect(x: -150, y: 70, width: 50, height: 20),
      screen: CGRect(x: -200, y: 0, width: 200, height: 100), image: image(400, 200))
    XCTAssertEqual(r, CGRect(x: 100, y: 20, width: 100, height: 40))
  }
  func testAbovePrimaryDisplay() {
    let r = Geometry.pixelCrop(
      selection: CGRect(x: 20, y: 140, width: 30, height: 30),
      screen: CGRect(x: 0, y: 100, width: 200, height: 100), image: image())
    XCTAssertEqual(r, CGRect(x: 20, y: 30, width: 30, height: 30))
  }
  func testMixedScaleCompositionAcrossDisplayBoundary() {
    let a = DisplayShot(
      frame: CGRect(x: -100, y: 0, width: 100, height: 100), image: image(100, 100, .red))
    let b = DisplayShot(
      frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: image(200, 200, .blue))
    let output = Raster.compose([a, b], selection: CGRect(x: -50, y: 20, width: 100, height: 40))!
    XCTAssertEqual(output.width, 200)
    XCTAssertEqual(output.height, 80)
    XCTAssertGreaterThan(pixel(output, 20, 20)[0], 240)
    XCTAssertGreaterThan(pixel(output, 180, 20)[2], 240)
    XCTAssertNil(Raster.compose([a], selection: .zero))
  }
  func testVerticalOrientationIsPreserved() {
    let c = CGContext(
      data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(NSColor.red.cgColor)
    c.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
    c.setFillColor(NSColor.blue.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
    let source = c.makeImage()!
    let shot = DisplayShot(frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: source)
    let output = Raster.compose([shot], selection: CGRect(x: 0, y: 50, width: 100, height: 50))!
    XCTAssertGreaterThan(pixel(output, 10, 10)[0], 240)
    let canvas = Canvas(image: source)
    let flattened = canvas.flattened()!
    XCTAssertEqual(pixel(flattened, 10, 10), pixel(source, 10, 10))
    XCTAssertEqual(pixel(flattened, 10, 80), pixel(source, 10, 80))
  }
  func testCoverIsOpaqueInFlattenedPNGAndUndoRestores() {
    let canvas = Canvas(image: image())
    canvas.marks = [Mark(tool: .cover, start: CGPoint(x: 20, y: 10), end: CGPoint(x: 100, y: 60))]
    let output = canvas.flattened()!
    XCTAssertEqual(pixel(output, 30, 20), [0, 0, 0, 255])
    XCTAssertEqual(pixel(output, 150, 20), [255, 255, 255, 255])
    let decoded = NSBitmapImageRep(data: Raster.png(output)!)!.cgImage!
    XCTAssertEqual(pixel(decoded, 30, 20), [0, 0, 0, 255])
    canvas.undoMark()
    XCTAssertEqual(pixel(canvas.flattened()!, 30, 20), [255, 255, 255, 255])
  }
  @MainActor func testOverlayEscapeRemovesEveryWindow() {
    _ = NSApplication.shared
    let coordinator = CaptureCoordinator()
    coordinator.shots = [
      DisplayShot(frame: CGRect(x: 0, y: 0, width: 200, height: 100), image: image()),
      DisplayShot(frame: CGRect(x: 200, y: 0, width: 200, height: 100), image: image()),
    ]
    coordinator.active = true
    coordinator.present()
    let windows = coordinator.windows
    XCTAssertEqual(windows.count, 2)
    let escape = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: windows[0].windowNumber, context: nil, characters: "\u{1b}",
      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    (windows[0].contentView as! SelectionView).keyDown(with: escape)
    XCTAssertTrue(coordinator.windows.isEmpty)
    XCTAssertFalse(coordinator.active)
    XCTAssertTrue(windows.allSatisfy { !$0.isVisible })
  }
  @MainActor func testEditorAndPinLifecycle() {
    _ = NSApplication.shared
    let editor = Editor(image: image())
    editor.showWindow(nil)
    XCTAssertTrue(editor.window!.isVisible)
    editor.canvas.marks.append(Mark(tool: .box, start: .zero, end: CGPoint(x: 60, y: 60)))
    editor.undoAction()
    XCTAssertTrue(editor.canvas.marks.isEmpty)
    let pin = Pin(image: editor.canvas.flattened()!)
    pin.showWindow(nil)
    XCTAssertEqual(pin.window!.level, .floating)
    let item = NSMenuItem()
    item.tag = 40
    pin.opacity(item)
    XCTAssertEqual(pin.window!.alphaValue, 0.4, accuracy: 0.01)
    pin.window!.setContentSize(CGSize(width: 400, height: 200))
    XCTAssertEqual(pin.window!.contentView!.bounds.width, 400)
    pin.window!.orderOut(nil)
    XCTAssertFalse(pin.window!.isVisible)
    pin.showWindow(nil)
    XCTAssertTrue(pin.window!.isVisible)
    var closed = false
    pin.closed = { closed = true }
    pin.close()
    XCTAssertTrue(closed)
    editor.close()
  }
  @MainActor func testSettingsAndGroupPinControls() throws {
    _ = NSApplication.shared
    NSApp.finishLaunching()
    let app = AppDelegate()
    app.showSettings()
    let settings = try XCTUnwrap(app.settings?.window)
    XCTAssertTrue(settings.isVisible)
    settings.layoutIfNeeded()
    settings.display()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let view = try XCTUnwrap(settings.contentView)
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".build/qa")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(
      to: directory.appendingPathComponent("settings.png"))
    app.addPin(image())
    app.addPin(image())
    XCTAssertEqual(app.pins.count, 2)
    app.togglePins()
    XCTAssertTrue(app.pins.values.allSatisfy { !$0.window!.isVisible })
    app.togglePins()
    XCTAssertTrue(app.pins.values.allSatisfy { $0.window!.isVisible })
    app.closePins()
    XCTAssertTrue(app.pins.isEmpty)
    settings.close()
    let editor = Editor(image: image(960, 600, .systemTeal))
    editor.showWindow(nil)
    editor.window?.layoutIfNeeded()
    editor.window?.display()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    editor.canvas.marks = [
      Mark(tool: .arrow, start: CGPoint(x: 100, y: 120), end: CGPoint(x: 300, y: 220)),
      Mark(
        tool: .text, start: CGPoint(x: 100, y: 300), end: .zero,
        text: "Stillpin — synthetic practice"),
      Mark(tool: .cover, start: CGPoint(x: 500, y: 100), end: CGPoint(x: 800, y: 200)),
    ]
    let content = editor.window!.contentView!
    let screenshot = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: screenshot)
    try screenshot.representation(using: .png, properties: [:])!.write(
      to: directory.appendingPathComponent("editor.png"))
    editor.close()
  }

  @MainActor func testAnnotationCopyPinRoundTripWithIsolatedPasteboard() throws {
    _ = NSApplication.shared
    let editor = Editor(image: image())
    editor.showWindow(nil)
    editor.canvas.tool = .cover
    func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: editor.canvas.convert(point, to: nil), modifierFlags: [],
        timestamp: 0, windowNumber: editor.window!.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1)!
    }
    editor.canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 20, y: 10)))
    editor.canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 100, y: 60)))
    editor.canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 100, y: 60)))
    XCTAssertEqual(editor.canvas.marks.count, 1)
    let pasteboard = NSPasteboard.withUniqueName()
    defer {
      pasteboard.releaseGlobally()
      editor.close()
    }
    editor.copy(to: pasteboard)
    let data = try XCTUnwrap(pasteboard.data(forType: .png))
    let decoded = try XCTUnwrap(NSBitmapImageRep(data: data)?.cgImage)
    XCTAssertEqual(pixel(decoded, 30, 20), [0, 0, 0, 255])
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
      ".build/roundtrip.png")
    try data.write(to: url, options: .atomic)
    XCTAssertEqual(try Data(contentsOf: url), data)
    let app = AppDelegate()
    app.pin(from: pasteboard)
    XCTAssertEqual(app.pins.count, 1)
    let view = try XCTUnwrap(app.pins.values.first?.window?.contentView as? PinImageView)
    let pinned = try XCTUnwrap(view.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    XCTAssertEqual(pixel(pinned, 30, 20), [0, 0, 0, 255])
    let menu = try XCTUnwrap(view.menu(for: event(.rightMouseDown, .zero)))
    XCTAssertEqual(menu.items.filter { $0.action == #selector(Pin.opacity(_:)) }.count, 5)
    app.closePins()
  }

}
