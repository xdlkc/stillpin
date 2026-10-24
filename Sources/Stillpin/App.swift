import AppKit
import Carbon

final class Hotkeys {
  var refs: [EventHotKeyRef] = []
  var handler: EventHandlerRef?
  var action: ((UInt32) -> Void)?
  static let keys: [(String, UInt32)] = [
    ("S", 1), ("P", 35), ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109),
  ]
  init() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue().action?(id.id)
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }
  func disable() {
    refs.forEach { UnregisterEventHotKey($0) }
    refs = []
  }
  func apply(enabled: Bool, capture: Int, pin: Int, modifiers: UInt32) -> Bool {
    disable()
    guard enabled else { return true }
    guard Self.keys.indices.contains(capture), Self.keys.indices.contains(pin), capture != pin,
      modifiers != 0
    else { return false }
    for (index, key) in [capture, pin].enumerated() {
      var ref: EventHotKeyRef?
      let status = RegisterEventHotKey(
        Self.keys[key].1, modifiers, EventHotKeyID(signature: 0x5354_504E, id: UInt32(index + 1)),
        GetApplicationEventTarget(), 0, &ref)
      guard status == noErr, let ref else {
        disable()
        return false
      }
      refs.append(ref)
    }
    return true
  }
  deinit {
    disable()
    if let handler { RemoveEventHandler(handler) }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  var status: NSStatusItem!
  let capture = CaptureCoordinator(), hotkeys = Hotkeys()
  var editors: [UUID: Editor] = [:], pins: [UUID: Pin] = [:]
  var settings: NSWindowController?
  var hidden = false
  var captureKey = NSPopUpButton(), pinKey = NSPopUpButton()
  var enabled = NSButton(checkboxWithTitle: "Enable global shortcuts", target: nil, action: nil)
  var modifierButtons: [NSButton] = []
  var permissionLabel = NSTextField(labelWithString: "")
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.image = NSImage(
      systemSymbolName: "pin.square", accessibilityDescription: "Stillpin")
    let menu = NSMenu()
    for (title, sel, key) in [
      ("Capture Region…", #selector(captureRegion), ""),
      ("Pin Clipboard Image", #selector(pinClipboard), ""),
      ("Open Image…", #selector(openImage), "o"),
      ("Synthetic Practice Image", #selector(practice), ""),
      ("Hide / Show All Pins", #selector(togglePins), ""),
      ("Close All Pins", #selector(closePins), ""),
      ("Settings & Permissions…", #selector(showSettings), ","),
      ("Quit Stillpin", #selector(quit), "q"),
    ] {
      let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
      i.target = self
      menu.addItem(i)
    }
    status.menu = menu
    let main = NSMenu()
    let app = NSMenuItem()
    app.submenu = menu.copy() as? NSMenu
    main.addItem(app)
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let edit = NSMenu()
    for (title, selector, key) in [
      ("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
      ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
    hotkeys.action = { [weak self] id in
      DispatchQueue.main.async {
        if id == 1 { self?.captureRegion() } else { self?.pinClipboard() }
      }
    }
    let d = UserDefaults.standard
    if !hotkeys.apply(
      enabled: !CommandLine.arguments.contains("--smoke-test")
        && !CommandLine.arguments.contains("--verify-capture") && d.bool(forKey: "hotkeys"),
      capture: d.integer(forKey: "captureKey"),
      pin: d.object(forKey: "pinKey") == nil ? 1 : d.integer(forKey: "pinKey"),
      modifiers: UInt32(d.integer(forKey: "modifiers")))
    {
      Self.alert(
        "Shortcuts unavailable",
        "Another application may use these shortcuts. Choose different keys in Settings.")
    }
    if CommandLine.arguments.contains("--verify-capture") {
      Task { await CaptureVerification.run(app: self) }
      return
    }
    if CommandLine.arguments.contains("--smoke-test") {
      showSettings()
      practice()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
        let okay =
          status.menu?.items.count == 8 && settings?.window?.isVisible == true && editors.count == 1
        print(okay ? "STILLPIN_SMOKE_PASS menu settings editor" : "STILLPIN_SMOKE_FAIL")
        for editor in Array(editors.values) { editor.close() }
        settings?.close()
        NSApp.terminate(nil)
      }
      return
    }
    if CommandLine.arguments.contains("--practice") {
      practice()
    } else if !d.bool(forKey: "welcomed") {
      showSettings()
      d.set(true, forKey: "welcomed")
    }
  }
  static func alert(_ title: String, _ message: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.runModal()
  }
  @objc func captureRegion() {
    guard CGPreflightScreenCaptureAccess() else {
      showSettings()
      Self.alert(
        "Screen Recording permission required",
        "Stillpin (app.xdlkc.stillpin) needs Screen Recording to capture the region you select. In Settings, choose Request Screen Recording, then approve Stillpin in macOS. No screen content leaves this Mac."
      )
      return
    }
    capture.begin { [weak self] image in self?.edit(image) }
  }
  func edit(_ image: CGImage) {
    let id = UUID()
    let e = Editor(image: image)
    e.closed = { [weak self] in self?.editors[id] = nil }
    editors[id] = e
    e.showWindow(nil)
    e.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func addPin(_ image: CGImage) {
    let id = UUID()
    let p = Pin(image: image)
    p.closed = { [weak self] in self?.pins[id] = nil }
    pins[id] = p
    hidden = false
    pins.values.forEach { $0.showWindow(nil) }
    p.showWindow(nil)
  }
  @objc func pinClipboard() { pin(from: .general) }
  func pin(from pasteboard: NSPasteboard) {
    guard let image = NSImage(pasteboard: pasteboard),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      Self.alert(
        "No clipboard image",
        "Copy an image first, or use Open Image. Stillpin only reads the clipboard when you choose this command."
      )
      return
    }
    addPin(cg)
  }
  @objc func openImage() {
    let p = NSOpenPanel()
    p.allowedContentTypes = [.png, .jpeg, .tiff]
    p.allowsMultipleSelection = false
    p.begin { result in
      if result == .OK, let url = p.url, let i = NSImage(contentsOf: url),
        let cg = i.cgImage(forProposedRect: nil, context: nil, hints: nil)
      {
        self.edit(cg)
      }
    }
  }
  @objc func practice() {
    let c = CGContext(
      data: nil, width: 960, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.25, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: 960, height: 600))
    c.setFillColor(NSColor.systemTeal.cgColor)
    c.fillEllipse(in: CGRect(x: 100, y: 100, width: 300, height: 300))
    edit(c.makeImage()!)
  }
  @objc func togglePins() {
    hidden.toggle()
    pins.values.forEach { hidden ? $0.window?.orderOut(nil) : $0.showWindow(nil) }
  }
  @objc func closePins() {
    let all = Array(pins.values)
    all.forEach { $0.close() }
    pins.removeAll()
  }
  @objc func quit() {
    capture.cancel()
    NSApp.terminate(nil)
  }
  @objc func showSettings() {
    if let settings {
      settings.showWindow(nil)
      settings.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      updatePermission()
      return
    }
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 650, height: 600), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    w.title = "Stillpin — Settings"
    w.isReleasedWhenClosed = false
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    w.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 24),
      stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -24),
    ])
    let title = NSTextField(labelWithString: "Stillpin • Capture, annotate, keep in view")
    title.font = .boldSystemFont(ofSize: 20)
    stack.addArrangedSubview(title)
    let info = NSTextField(
      wrappingLabelWithString:
        "Local-only images. No telemetry, account, Accessibility permission, or clipboard monitoring. Use the menu bar pin icon to capture, open an image, or pin a copied image."
    )
    stack.addArrangedSubview(info)
    stack.addArrangedSubview(permissionLabel)
    let row = NSStackView(views: [
      NSButton(
        title: "Request Screen Recording", target: self, action: #selector(requestPermission)),
      NSButton(title: "Open Privacy Settings", target: self, action: #selector(privacy)),
    ])
    stack.addArrangedSubview(row)
    let d = UserDefaults.standard
    enabled.state = d.bool(forKey: "hotkeys") ? .on : .off
    stack.addArrangedSubview(enabled)
    captureKey.addItems(withTitles: Hotkeys.keys.map { $0.0 })
    pinKey.addItems(withTitles: Hotkeys.keys.map { $0.0 })
    captureKey.selectItem(at: min(6, d.integer(forKey: "captureKey")))
    pinKey.selectItem(
      at: d.object(forKey: "pinKey") == nil ? 1 : min(6, d.integer(forKey: "pinKey")))
    stack.addArrangedSubview(
      NSStackView(views: [
        NSTextField(labelWithString: "Capture"), captureKey,
        NSTextField(labelWithString: "Pin clipboard"), pinKey,
      ]))
    let mods = NSStackView()
    let stored =
      d.object(forKey: "modifiers") == nil
      ? UInt32(cmdKey | optionKey | controlKey) : UInt32(d.integer(forKey: "modifiers"))
    for (label, value) in [
      ("⌘ Command", cmdKey), ("⌥ Option", optionKey), ("⌃ Control", controlKey),
      ("⇧ Shift", shiftKey),
    ] {
      let b = NSButton(checkboxWithTitle: label, target: nil, action: nil)
      b.tag = value
      b.state = (stored & UInt32(value)) != 0 ? .on : .off
      modifierButtons.append(b)
      mods.addArrangedSubview(b)
    }
    stack.addArrangedSubview(mods)
    stack.addArrangedSubview(
      NSButton(title: "Apply Shortcuts", target: self, action: #selector(applyShortcuts)))
    stack.addArrangedSubview(
      NSTextField(
        wrappingLabelWithString:
          "Shortcuts start disabled. Capture: drag a region, Esc cancels. Editor: choose a tool then drag; Text prompts for text; ⌘Z undoes. Pins: drag title bar, resize edges, right-click for opacity or close. Ad-hoc signed; not notarized."
      ))
    settings = NSWindowController(window: w)
    w.center()
    settings?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    updatePermission()
  }
  func updatePermission() {
    permissionLabel.stringValue =
      "Screen Recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted") • app.xdlkc.stillpin"
  }
  @objc func requestPermission() {
    _ = CGRequestScreenCaptureAccess()
    updatePermission()
  }
  @objc func privacy() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
  }
  @objc func applyShortcuts() {
    let mods = modifierButtons.filter { $0.state == .on }.reduce(UInt32(0)) { $0 | UInt32($1.tag) }
    let on = enabled.state == .on
    guard
      hotkeys.apply(
        enabled: on, capture: captureKey.indexOfSelectedItem, pin: pinKey.indexOfSelectedItem,
        modifiers: mods)
    else {
      UserDefaults.standard.set(false, forKey: "hotkeys")
      enabled.state = .off
      Self.alert(
        "Shortcuts not registered",
        "Choose distinct keys with at least one modifier. A system or application shortcut may already own that combination. Stillpin shortcuts are now disabled."
      )
      return
    }
    let d = UserDefaults.standard
    d.set(on, forKey: "hotkeys")
    d.set(captureKey.indexOfSelectedItem, forKey: "captureKey")
    d.set(pinKey.indexOfSelectedItem, forKey: "pinKey")
    d.set(Int(mods), forKey: "modifiers")
  }
}
