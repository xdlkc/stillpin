import AppKit

enum EditorCommand: Equatable {
  case copy, save, pin, undo, redo, copyAndClose, cancel, text
  static func resolve(_ event: NSEvent) -> Self? {
    let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
    let text = event.charactersIgnoringModifiers?.lowercased()
    if mods == .command {
      switch text {
      case "c": return .copy
      case "s": return .save
      case "t": return .pin
      case "z": return .undo
      default: return nil
      }
    }
    if mods == [.command, .shift], text == "z" { return .redo }
    if mods.isEmpty {
      if event.keyCode == 36 || event.keyCode == 76 { return .copyAndClose }
      if event.keyCode == 53
        && event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
      {
        return .cancel
      }
      if text == "t" { return .text }
    }
    return nil
  }
}
final class EditorWindow: NSWindow {
  var command: ((NSEvent) -> Bool)?
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if !(firstResponder is NSText), command?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }
}
@MainActor final class Editor: NSWindowController, NSWindowDelegate {
  let canvas: Canvas
  var copyPasteboard: NSPasteboard = .general
  var toolPicker: NSSegmentedControl?
  var closed: (() -> Void)?
  init(image: CGImage) {
    canvas = Canvas(image: image)
    let w = EditorWindow(
      contentRect: CGRect(x: 0, y: 0, width: 920, height: 650),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
    )
    super.init(window: w)
    w.command = { [weak self] in self?.handle($0) ?? false }
    canvas.command = { [weak self] in self?.handle($0) ?? false }
    w.minSize = CGSize(width: 820, height: 360)
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
    toolPicker = tools
    bar.addArrangedSubview(tools)
    for (title, action) in [
      ("Undo", #selector(undoAction)), ("Redo", #selector(redoAction)),
      ("Copy", #selector(copyImage)),
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
    w.initialFirstResponder = canvas
    scroll.magnification = min(1, min(900 / CGFloat(image.width), 570 / CGFloat(image.height)))
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func changeTool(_ sender: NSSegmentedControl) {
    canvas.tool = Tool.allCases[sender.selectedSegment]
  }
  @objc func undoAction() { canvas.undoMark() }
  @objc func redoAction() { canvas.redoMark() }
  func handle(_ event: NSEvent) -> Bool {
    guard let command = EditorCommand.resolve(event) else { return false }
    switch command {
    case .copy: copyImage()
    case .save: saveImage()
    case .pin: pinImage()
    case .undo: undoAction()
    case .redo: redoAction()
    case .copyAndClose:
      copyImage()
      close()
    case .cancel: close()
    case .text:
      canvas.tool = .text
      toolPicker?.selectedSegment = Tool.allCases.firstIndex(of: .text) ?? 2
    }
    return true
  }

  @objc func copyImage() { copy(to: copyPasteboard) }
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
final class PinPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
      event.charactersIgnoringModifiers?.lowercased() == "w"
    {
      performClose(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53
      && event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
    {
      performClose(nil)
    } else {
      super.keyDown(with: event)
    }
  }
}
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
