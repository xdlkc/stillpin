import AppKit
import Carbon

struct Shortcut: Codable, Hashable {
  var keyCode: UInt32
  var modifiers: UInt32
  static let choices: [(String, UInt32)] = [
    ("S", 1), ("P", 35), ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109),
    ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F11", 103), ("F12", 111),
    ("C", 8), ("T", 17), ("W", 13), ("Z", 6),
  ]
  static let modifierChoices: [(String, UInt32)] = [
    ("⌘", UInt32(cmdKey)), ("⌥", UInt32(optionKey)), ("⌃", UInt32(controlKey)),
    ("⇧", UInt32(shiftKey)),
  ]
  var label: String {
    Self.modifierChoices.filter { modifiers & $0.1 != 0 }.map(\.0).joined()
      + (Self.choices.first { $0.1 == keyCode }?.0 ?? "Key \(keyCode)")
  }
  var valid: Bool {
    let supported = Self.choices.contains { $0.1 == keyCode }
    let known = Self.modifierChoices.reduce(UInt32(0)) { $0 | $1.1 }
    let functionKey = Self.choices.contains { $0.1 == keyCode && $0.0.hasPrefix("F") }
    return supported && modifiers & ~known == 0 && (modifiers != 0 || functionKey)
  }
}
struct ShortcutConfiguration: Codable, Equatable {
  var enabled: Bool
  var capture: Shortcut
  var pin: Shortcut
  var toggle: Shortcut
  static let defaults = Self(
    enabled: true, capture: Shortcut(keyCode: 122, modifiers: 0),
    pin: Shortcut(keyCode: 99, modifiers: 0),
    toggle: Shortcut(keyCode: 99, modifiers: UInt32(shiftKey)))
  var bindings: [(String, Shortcut)] {
    [("Capture", capture), ("Pin clipboard", pin), ("Hide/show pins", toggle)]
  }
}
enum ShortcutPreferences {
  static let key = "shortcutConfigurationV2"
  static let legacyKeys = ["hotkeys", "captureKey", "pinKey", "modifiers"]
  /// The old app persisted no key defaults until Apply was clicked. Even a tuple equal to its old
  /// suggestions is explicit intent, so never guess that it is safe to overwrite it.
  static func migrated(_ legacy: [String: Any]) -> ShortcutConfiguration {
    guard legacyKeys.contains(where: { legacy[$0] != nil }) else { return .defaults }
    var config = ShortcutConfiguration.defaults
    config.enabled = (legacy["hotkeys"] as? Bool) ?? false
    if ["captureKey", "pinKey", "modifiers"].contains(where: { legacy[$0] != nil }) {
      let oldKeys = Array(Shortcut.choices.prefix(7))
      func code(_ name: String, fallback: Int) -> UInt32 {
        let index = (legacy[name] as? Int) ?? fallback
        return oldKeys.indices.contains(index) ? oldKeys[index].1 : UInt32.max
      }
      let raw = (legacy["modifiers"] as? Int) ?? 0
      let mods = UInt32(exactly: raw) ?? UInt32.max
      config.capture = Shortcut(keyCode: code("captureKey", fallback: 0), modifiers: mods)
      config.pin = Shortcut(keyCode: code("pinKey", fallback: 1), modifiers: mods)
    }
    return config
  }
  static func load(_ defaults: UserDefaults) -> ShortcutConfiguration {
    if let data = defaults.data(forKey: key),
      let value = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data)
    {
      return value
    }
    let legacy = Dictionary(
      uniqueKeysWithValues: legacyKeys.compactMap { name in
        defaults.object(forKey: name).map { (name, $0) }
      })
    let config = migrated(legacy)
    save(config, to: defaults)
    return config
  }
  static func save(_ config: ShortcutConfiguration, to defaults: UserDefaults) {
    if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: key) }
  }
}
final class Hotkeys {
  enum Registration {
    case success(() -> Void)
    case failure(OSStatus)
  }
  var releaseHandlers: [() -> Void] = []
  var handler: EventHandlerRef?
  var action: ((UInt32) -> Void)?
  var register: (Shortcut, UInt32) -> Registration
  var reserved: () -> Set<Shortcut>
  init(
    register: ((Shortcut, UInt32) -> Registration)? = nil, reserved: (() -> Set<Shortcut>)? = nil
  ) {
    self.register =
      register ?? { binding, id in
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
          binding.keyCode, binding.modifiers, EventHotKeyID(signature: 0x5354_504E, id: id),
          GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
        guard status == noErr, let ref else { return .failure(status) }
        return .success { UnregisterEventHotKey(ref) }
      }
    self.reserved = reserved ?? Self.systemReserved
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
        guard id.signature == 0x5354_504E else { return OSStatus(eventNotHandledErr) }
        Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue().action?(id.id)
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }
  static func systemReserved() -> Set<Shortcut> {
    var array: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&array) == noErr,
      let entries = array?.takeRetainedValue() as? [[String: Any]]
    else { return [] }
    return Set(
      entries.compactMap { entry in
        guard (entry[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
          let code = entry[kHISymbolicHotKeyCode as String] as? NSNumber,
          let mods = entry[kHISymbolicHotKeyModifiers as String] as? NSNumber
        else { return nil }
        return Shortcut(keyCode: code.uint32Value, modifiers: mods.uint32Value)
      })
  }
  func disable() {
    releaseHandlers.forEach { $0() }
    releaseHandlers = []
  }
  /// Failure releases every registration from this attempt, but never edits the user's preferences.
  func apply(_ config: ShortcutConfiguration) -> String? {
    disable()
    guard config.enabled else { return nil }
    let bindings = config.bindings
    guard bindings.allSatisfy({ $0.1.valid }) else {
      return "Unsupported key or modifier. Bare keys must be function keys."
    }
    guard Set(bindings.map(\.1)).count == bindings.count else {
      return "Two actions use the same shortcut. Choose distinct combinations."
    }
    let reserved = reserved()
    for (index, entry) in bindings.enumerated() {
      if reserved.contains(entry.1) {
        disable()
        return
          "\(entry.0) (\(entry.1.label)) is reserved by macOS. Choose another shortcut; Stillpin did not change system settings."
      }
      switch register(entry.1, UInt32(index + 1)) {
      case .success(let release): releaseHandlers.append(release)
      case .failure(let status):
        disable()
        return
          "\(entry.0) (\(entry.1.label)) could not register (macOS status \(status)); another app may own it. All Stillpin global shortcuts are inactive. Your saved keys are preserved."
      }
    }
    return nil
  }
  deinit {
    disable()
    if let handler { RemoveEventHandler(handler) }
  }
}
@MainActor final class ShortcutRow {
  let view = NSStackView()
  let key = NSPopUpButton()
  var modifiers: [NSButton] = []
  init(title: String) {
    let label = NSTextField(labelWithString: title)
    label.widthAnchor.constraint(equalToConstant: 120).isActive = true
    view.addArrangedSubview(label)
    key.addItems(withTitles: Shortcut.choices.map(\.0))
    view.addArrangedSubview(key)
    for (title, value) in Shortcut.modifierChoices {
      let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
      button.tag = Int(value)
      modifiers.append(button)
      view.addArrangedSubview(button)
    }
  }
  func set(_ value: Shortcut) {
    if let index = Shortcut.choices.firstIndex(where: { $0.1 == value.keyCode }) {
      key.selectItem(at: index)
    } else {
      key.selectItem(at: -1)
    }
    for button in modifiers {
      button.state = value.modifiers & UInt32(button.tag) != 0 ? .on : .off
    }
  }
  var value: Shortcut {
    let index = key.indexOfSelectedItem
    return Shortcut(
      keyCode: Shortcut.choices.indices.contains(index) ? Shortcut.choices[index].1 : UInt32.max,
      modifiers: modifiers.filter { $0.state == .on }.reduce(0) { $0 | UInt32($1.tag) })
  }
}
