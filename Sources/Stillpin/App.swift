import AppKit
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  var status: NSStatusItem!
  let capture = CaptureCoordinator(), hotkeys = Hotkeys()
  var editors: [UUID: Editor] = [:], pins: [UUID: Pin] = [:]
  var settings: NSWindowController?
  var hidden = false
  var configuration = ShortcutConfiguration.defaults
  var shortcutRows: [ShortcutRow] = []
  var shortcutError: String?
  var shortcutStatus = NSTextField(wrappingLabelWithString: "")
  var enabled = NSButton(checkboxWithTitle: "Enable global shortcuts", target: nil, action: nil)
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
        switch id {
        case 1: self?.captureRegion()
        case 2: self?.pinClipboard()
        case 3: self?.togglePins()
        default: break
        }
      }
    }
    let d = UserDefaults.standard
    let testing =
      CommandLine.arguments.contains("--smoke-test")
      || CommandLine.arguments.contains("--verify-capture")
      || CommandLine.arguments.contains("--verify-hotkeys")
    if !testing {
      configuration = ShortcutPreferences.load(d)
      shortcutError = hotkeys.apply(configuration)
      if let shortcutError {
        Self.alert(
          "Shortcuts unavailable",
          shortcutError
            + "\nOpen Settings to choose unused keys or disable shortcuts. No other app was changed."
        )
      }
    }
    updateShortcutStatus()
    if CommandLine.arguments.contains("--verify-hotkeys") {
      hotkeys.action = nil  // Registration probe must never execute capture or clipboard actions.
      let result = hotkeys.apply(.defaults)
      print(
        result.map { "STILLPIN_HOTKEY_REGISTRATION_CONFLICT: \($0)" }
          ?? "STILLPIN_HOTKEY_REGISTRATION_PASS: F1, F3, Shift+F3")
      hotkeys.disable()
      NSApp.terminate(nil)
      return
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
      contentRect: CGRect(x: 0, y: 0, width: 680, height: 690), styleMask: [.titled, .closable],
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
    enabled.state = configuration.enabled ? .on : .off
    stack.addArrangedSubview(enabled)
    for (title, binding) in configuration.bindings {
      let row = ShortcutRow(title: title)
      row.set(binding)
      shortcutRows.append(row)
      stack.addArrangedSubview(row.view)
    }
    stack.addArrangedSubview(
      NSStackView(views: [
        NSButton(title: "Apply Shortcuts", target: self, action: #selector(applyShortcuts)),
        NSButton(
          title: "Restore Snipaste Defaults", target: self, action: #selector(restoreShortcuts)),
      ]))
    stack.addArrangedSubview(shortcutStatus)
    stack.addArrangedSubview(
      NSTextField(
        wrappingLabelWithString:
          "Defaults: F1 capture, F3 pin clipboard, ⇧F3 hide/show pins. Mac media keys may require Fn; Stillpin never changes system settings. Editor: ⌘C copy, ⌘S save, ⌘T pin, ⌘Z undo, ⌘⇧Z redo, Enter copy and close, T text. Pins: Esc or ⌘W closes. Ad-hoc signed; not notarized."
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
  func updateShortcutStatus() {
    shortcutStatus.stringValue =
      shortcutError.map { "Inactive: " + $0 }
      ?? (configuration.enabled
        ? "Global shortcuts enabled: "
          + configuration.bindings.map { $0.1.label }.joined(separator: " / ")
        : "Global shortcuts disabled")
    for menu in [status?.menu, NSApp.mainMenu?.items.first?.submenu].compactMap({ $0 }) {
      for (index, actionIndex) in [(0, 0), (1, 1), (4, 2)] where menu.items.indices.contains(index)
      {
        let titles = ["Capture Region…", "Pin Clipboard Image", "Hide / Show All Pins"]
        let suffix =
          configuration.enabled && shortcutError == nil
          ? configuration.bindings[actionIndex].1.label : "inactive"
        menu.items[index].title = titles[actionIndex] + "  [" + suffix + "]"
      }
    }
  }
  @objc func restoreShortcuts() {
    configuration = .defaults
    enabled.state = .on
    for (row, binding) in zip(shortcutRows, configuration.bindings) { row.set(binding.1) }
    applyShortcuts()
  }
  @objc func applyShortcuts() {
    guard shortcutRows.count == 3 else { return }
    configuration = ShortcutConfiguration(
      enabled: enabled.state == .on, capture: shortcutRows[0].value, pin: shortcutRows[1].value,
      toggle: shortcutRows[2].value)
    ShortcutPreferences.save(configuration, to: .standard)
    shortcutError = hotkeys.apply(configuration)
    updateShortcutStatus()
    if let shortcutError { Self.alert("Shortcuts not registered", shortcutError) }
  }
}
