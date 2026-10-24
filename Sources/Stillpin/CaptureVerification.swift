import AppKit
import ScreenCaptureKit

/// Explicit developer-only verification. Never run from CI: requires Stillpin's user-granted TCC access.
/// A synthetic opaque window covers the selected display before it is captured. Only an inset region
/// of that window may be saved; the user's surrounding desktop is never exported.
@MainActor enum CaptureVerification {
  static func run(app: AppDelegate) async {
    guard CGPreflightScreenCaptureAccess() else {
      print(
        "STILLPIN_CAPTURE_PENDING: Approve Screen Recording for Stillpin (app.xdlkc.stillpin) in its Settings, then rerun."
      )
      NSApp.terminate(nil)
      return
    }
    var fixture: NSWindow?
    defer { fixture?.close() }
    do {
      guard let screen = NSScreen.main,
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
      else { throw Failure("No display is available") }
      let frame = screen.frame
      let window = OverlayWindow(
        contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.level = .screenSaver
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.isOpaque = true
      window.backgroundColor = .white
      fixture = window
      window.makeKeyAndOrderFront(nil)
      window.display()
      // Let the compositor present only our opaque, non-sensitive fixture before requesting a frame.
      try await Task.sleep(nanoseconds: 500_000_000)
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
      guard let display = content.displays.first(where: { $0.displayID == id }) else {
        throw Failure("Display changed")
      }
      let image = try await FrameGrabber.capture(
        display,
        pixelSize: CGSize(
          width: frame.width * screen.backingScaleFactor,
          height: frame.height * screen.backingScaleFactor))
      let selection = CGRect(x: frame.midX - 100, y: frame.midY - 60, width: 200, height: 120)
      guard
        let cropped = Raster.compose(
          [DisplayShot(frame: frame, image: image)], selection: selection),
        isWhite(cropped)
      else { throw Failure("Captured fixture pixels were not white; no image was saved") }
      window.orderOut(nil)
      let editor = Editor(image: cropped)
      editor.showWindow(nil)
      editor.canvas.marks = [
        Mark(tool: .cover, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 70))
      ]
      let board = NSPasteboard.withUniqueName()
      defer {
        board.releaseGlobally()
        editor.close()
        app.closePins()
      }
      editor.copy(to: board)
      guard let data = board.data(forType: .png),
        let decoded = NSBitmapImageRep(data: data)?.cgImage,
        isBlack(decoded, x: 20, y: 20)
      else { throw Failure("Flattened cover/copy verification failed") }
      let output = FileManager.default.temporaryDirectory.appendingPathComponent(
        "StillpinVerification/real-capture-fixture.png")
      try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: output, options: .atomic)
      guard try Data(contentsOf: output) == data else {
        throw Failure("PNG save verification failed")
      }
      app.pin(from: board)
      guard let pin = app.pins.values.first, pin.window?.isVisible == true,
        pin.window?.level == .floating
      else { throw Failure("Pin verification failed") }
      let item = NSMenuItem()
      item.tag = 60
      pin.opacity(item)
      guard abs((pin.window?.alphaValue ?? 0) - 0.6) < 0.01 else {
        throw Failure("Opacity verification failed")
      }
      app.togglePins()
      app.togglePins()
      let coordinator = CaptureCoordinator()
      coordinator.active = true
      coordinator.shots = [DisplayShot(frame: selection, image: cropped)]
      coordinator.present()
      let overlay = coordinator.windows[0]
      let escape = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: overlay.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
      (overlay.contentView as? SelectionView)?.keyDown(with: escape)
      guard coordinator.windows.isEmpty, !overlay.isVisible else {
        throw Failure("Escape cleanup failed")
      }
      print(
        "STILLPIN_REAL_CAPTURE_PASS: ScreenCaptureKit region, opaque cover, isolated clipboard, PNG save, pin, opacity, visibility, Escape cleanup. Fixture only; no desktop exported. Local PNG: \(output.path)"
      )
    } catch {
      print("STILLPIN_REAL_CAPTURE_FAIL: \(error.localizedDescription)")
    }
    fixture?.close()
    NSApp.terminate(nil)
  }
  private struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
  }
  private static func bytes(_ image: CGImage, x: Int, y: Int) -> [UInt8]? {
    guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
      let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return Array(
      UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 4))
  }
  private static func isWhite(_ image: CGImage) -> Bool {
    guard
      let c = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = c.data
    else { return false }
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let p = data.assumingMemoryBound(to: UInt8.self)
    // Require the ENTIRE captured crop to be the white fixture before anything can be saved.
    for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
      if p[offset] < 246 || p[offset + 1] < 246 || p[offset + 2] < 246 { return false }
    }
    return true
  }
  private static func isBlack(_ image: CGImage, x: Int, y: Int) -> Bool {
    guard let p = bytes(image, x: x, y: y) else { return false }
    return p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 255
  }
}
