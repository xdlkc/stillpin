import AppKit

@MainActor final class Editor: NSWindowController, NSWindowDelegate {
  let canvas: Canvas
  var closed: (() -> Void)?
  init(image: CGImage) {
    canvas = Canvas(image: image)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 920, height: 650),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
    )
    super.init(window: w)
    w.minSize = CGSize(width: 760, height: 360)
    w.title = "Stillpin — Annotate"
    w.isReleasedWhenClosed = false
    w.delegate = self
    let root = NSView()
    w.contentView = root
    let bar = NSStackView()
    bar.orientation = .horizontal
    bar.spacing = 8
    bar.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(bar)
    let tools = NSSegmentedControl(
      labels: Tool.allCases.map(\.rawValue), trackingMode: .selectOne, target: self,
      action: #selector(changeTool(_:)))
    tools.selectedSegment = 0
    bar.addArrangedSubview(tools)
    for (title, action) in [
      ("Undo", #selector(undoAction)), ("Copy", #selector(copyImage)),
      ("Save PNG…", #selector(saveImage)), ("Pin", #selector(pinImage)),
    ] { bar.addArrangedSubview(NSButton(title: title, target: self, action: action)) }
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.allowsMagnification = true
    scroll.minMagnification = 0.05
    scroll.maxMagnification = 4
    scroll.documentView = canvas
    scroll.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
      bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      bar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
      scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    w.center()
    w.layoutIfNeeded()
    scroll.magnification = min(1, min(900 / CGFloat(image.width), 570 / CGFloat(image.height)))
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func changeTool(_ sender: NSSegmentedControl) {
    canvas.tool = Tool.allCases[sender.selectedSegment]
  }
  @objc func undoAction() { canvas.undoMark() }
  @objc func copyImage() { copy(to: .general) }
  func copy(to pasteboard: NSPasteboard) {
    guard let i = canvas.flattened(), let data = Raster.png(i) else { return }
    pasteboard.clearContents()
    pasteboard.setData(data, forType: .png)
  }
  @objc func saveImage() {
    let p = NSSavePanel()
    p.allowedContentTypes = [.png]
    p.nameFieldStringValue = "Stillpin-\(Int(Date().timeIntervalSince1970)).png"
    p.beginSheetModal(for: window!) { response in
      if response == .OK, let url = p.url, let i = self.canvas.flattened(), let data = Raster.png(i)
      {
        do { try data.write(to: url, options: .atomic) } catch {
          AppDelegate.alert("Save failed", error.localizedDescription)
        }
      }
    }
  }
  @objc func pinImage() {
    if let i = canvas.flattened() { (NSApp.delegate as? AppDelegate)?.addPin(i) }
  }
  func windowWillClose(_ notification: Notification) { closed?() }
}
final class PinPanel: NSPanel { override var canBecomeKey: Bool { true } }
@MainActor final class Pin: NSWindowController, NSWindowDelegate {
  var closed: (() -> Void)?
  init(image: CGImage) {
    let scale = min(1, 600 / CGFloat(image.width))
    let size = CGSize(
      width: max(120, CGFloat(image.width) * scale), height: max(100, CGFloat(image.height) * scale)
    )
    let w = PinPanel(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
    super.init(window: w)
    w.title = "Stillpin • Drag / resize • Right-click for controls"
    w.level = .floating
    w.isReleasedWhenClosed = false
    w.isFloatingPanel = true
    w.hidesOnDeactivate = false
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    w.delegate = self
    w.contentAspectRatio = CGSize(width: image.width, height: image.height)
    w.minSize = CGSize(width: 100, height: 80)
    let view = PinImageView()
    view.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    view.imageScaling = .scaleProportionallyUpOrDown
    view.owner = self
    w.contentView = view
    w.isMovableByWindowBackground = true
    w.center()
  }
  required init?(coder: NSCoder) { fatalError() }
  func windowWillClose(_ notification: Notification) { closed?() }
  @objc func opacity(_ sender: NSMenuItem) { window?.alphaValue = CGFloat(sender.tag) / 100 }
  @objc func closePin() { close() }
}
@MainActor final class PinImageView: NSImageView {
  weak var owner: Pin?
  override func menu(for event: NSEvent) -> NSMenu? {
    let m = NSMenu()
    for n in [100, 80, 60, 40, 20] {
      let i = NSMenuItem(
        title: "Opacity \(n)%", action: #selector(Pin.opacity(_:)), keyEquivalent: "")
      i.tag = n
      i.target = owner
      m.addItem(i)
    }
    m.addItem(.separator())
    let close = NSMenuItem(title: "Close Pin", action: #selector(Pin.closePin), keyEquivalent: "")
    close.target = owner
    m.addItem(close)
    return m
  }
}
