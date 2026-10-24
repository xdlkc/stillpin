import AppKit
import CoreMedia
import ScreenCaptureKit

final class FrameGrabber: NSObject, SCStreamOutput, @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<CGImage, Error>?
  enum Failure: Error { case timeout, image }
  func receive(_ continuation: CheckedContinuation<CGImage, Error>) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()
  }
  func finish(_ result: Result<CGImage, Error>) {
    lock.lock()
    let c = continuation
    continuation = nil
    lock.unlock()
    c?.resume(with: result)
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
      let buffer = sampleBuffer.imageBuffer
    else { return }
    let ci = CIImage(cvPixelBuffer: buffer)
    if let image = CIContext().createCGImage(ci, from: ci.extent) { finish(.success(image)) }
  }
  static func capture(_ display: SCDisplay, pixelSize: CGSize) async throws -> CGImage {
    let receiver = FrameGrabber()
    let config = SCStreamConfiguration()
    config.width = Int(pixelSize.width)
    config.height = Int(pixelSize.height)
    config.showsCursor = false
    config.capturesAudio = false
    config.queueDepth = 1
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    try stream.addStreamOutput(
      receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "stillpin.capture"))
    do {
      let image = try await withCheckedThrowingContinuation {
        (c: CheckedContinuation<CGImage, Error>) in
        receiver.receive(c)
        Task { do { try await stream.startCapture() } catch { receiver.finish(.failure(error)) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
          receiver.finish(.failure(Failure.timeout))
        }
      }
      try? await stream.stopCapture()
      return image
    } catch {
      try? await stream.stopCapture()
      throw error
    }
  }
}
@MainActor final class CaptureCoordinator {
  var windows: [NSWindow] = []
  var shots: [DisplayShot] = []
  var anchor: CGPoint?
  var selection: CGRect = .zero
  var completion: ((CGImage) -> Void)?
  var active = false
  func begin(completion: @escaping (CGImage) -> Void) {
    guard !active else { return }
    active = true
    self.completion = completion
    Task {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        var result: [DisplayShot] = []
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        for screen in screens {
          guard
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
            let display = content.displays.first(where: { $0.displayID == id })
          else { throw FrameGrabber.Failure.image }
          let image = try await FrameGrabber.capture(
            display,
            pixelSize: CGSize(
              width: screen.frame.width * screen.backingScaleFactor,
              height: screen.frame.height * screen.backingScaleFactor))
          result.append(DisplayShot(frame: screen.frame, image: image))
        }
        guard !result.isEmpty, NSScreen.screens.map(\.frame) == frames else {
          throw FrameGrabber.Failure.image
        }
        shots = result
        present()
      } catch {
        cancel()
        AppDelegate.alert(
          "Screenshot unavailable",
          error.localizedDescription
            + "\nCheck Stillpin in System Settings → Privacy & Security → Screen Recording, then relaunch if macOS requests it."
        )
      }
    }
  }
  func present() {
    for shot in shots {
      let w = OverlayWindow(
        contentRect: shot.frame, styleMask: .borderless, backing: .buffered, defer: false)
      w.level = .screenSaver
      w.isOpaque = false
      w.backgroundColor = .clear
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      w.isReleasedWhenClosed = false
      let view = SelectionView(frame: CGRect(origin: .zero, size: shot.frame.size))
      view.owner = self
      view.shot = shot
      w.contentView = view
      windows.append(w)
      w.makeKeyAndOrderFront(nil)
      w.makeFirstResponder(view)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
  func update() { windows.forEach { $0.contentView?.needsDisplay = true } }
  func finish() {
    let output = Raster.compose(shots, selection: selection)
    let callback = completion
    cancel()
    if let output { callback?(output) }
  }
  func cancel() {
    windows.forEach {
      $0.orderOut(nil)
      $0.close()
    }
    windows = []
    shots = []
    anchor = nil
    selection = .zero
    active = false
    completion = nil
  }
}
final class OverlayWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor final class SelectionView: NSView {
  weak var owner: CaptureCoordinator?
  var shot: DisplayShot?
  override var acceptsFirstResponder: Bool { true }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
  override func draw(_ dirtyRect: NSRect) {
    guard let s = shot else { return }
    NSImage(cgImage: s.image, size: s.frame.size).draw(in: bounds)
    NSColor.black.withAlphaComponent(0.35).setFill()
    bounds.fill()
    if let r = owner?.selection.intersection(s.frame), !r.isNull {
      let local = r.offsetBy(dx: -s.frame.minX, dy: -s.frame.minY)
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: local).addClip()
      NSImage(cgImage: s.image, size: s.frame.size).draw(in: bounds)
      NSGraphicsContext.restoreGraphicsState()
      NSColor.systemOrange.setStroke()
      let p = NSBezierPath(rect: local.insetBy(dx: 1, dy: 1))
      p.lineWidth = 2
      p.stroke()
    }
    ("Drag to select • Esc to cancel" as NSString).draw(
      at: CGPoint(x: 24, y: 24),
      withAttributes: [
        .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .backgroundColor: NSColor.black,
      ])
  }
  override func mouseDown(with event: NSEvent) { owner?.anchor = NSEvent.mouseLocation }
  override func mouseDragged(with event: NSEvent) {
    if let a = owner?.anchor {
      owner?.selection = Geometry.rect(a, NSEvent.mouseLocation)
      owner?.update()
    }
  }
  override func mouseUp(with event: NSEvent) {
    if let a = owner?.anchor { owner?.selection = Geometry.rect(a, NSEvent.mouseLocation) }
    owner?.finish()
  }
  override func keyDown(with event: NSEvent) { if event.keyCode == 53 { owner?.cancel() } }
}
