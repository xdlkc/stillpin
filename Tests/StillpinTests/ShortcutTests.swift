import AppKit
import Carbon
import XCTest

@testable import Stillpin

final class ShortcutTests: XCTestCase {
  func key(_ text: String, code: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
      context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
      keyCode: code)!
  }
  func testOfficialCoreDefaultsAndBareFunctionKeys() {
    let c = ShortcutConfiguration.defaults
    XCTAssertTrue(c.enabled)
    XCTAssertEqual(c.capture, Shortcut(keyCode: 122, modifiers: 0))
    XCTAssertEqual(c.pin, Shortcut(keyCode: 99, modifiers: 0))
    XCTAssertEqual(c.toggle, Shortcut(keyCode: 99, modifiers: UInt32(shiftKey)))
    XCTAssertTrue(c.bindings.allSatisfy { $0.1.valid })
    XCTAssertFalse(Shortcut(keyCode: 1, modifiers: 0).valid)
    XCTAssertFalse(Shortcut(keyCode: 999, modifiers: UInt32(cmdKey)).valid)
  }
  func testLegacyUntouchedAndExplicitDisabledMigration() {
    XCTAssertEqual(ShortcutPreferences.migrated([:]), .defaults)
    XCTAssertEqual(ShortcutPreferences.migrated(["welcomed": true]), .defaults)
    var disabled = ShortcutConfiguration.defaults
    disabled.enabled = false
    XCTAssertEqual(ShortcutPreferences.migrated(["hotkeys": false]), disabled)
  }
  func testAllLegacyKeyIndicesAndExplicitOldSuggestedTuplePreserved() {
    for index in 0..<7 {
      let legacy: [String: Any] = [
        "hotkeys": true, "captureKey": index, "pinKey": (index + 1) % 7,
        "modifiers": cmdKey | optionKey | controlKey,
      ]
      let c = ShortcutPreferences.migrated(legacy)
      XCTAssertTrue(c.enabled)
      XCTAssertEqual(c.capture.keyCode, Shortcut.choices[index].1)
      XCTAssertEqual(c.pin.keyCode, Shortcut.choices[(index + 1) % 7].1)
      XCTAssertEqual(c.capture.modifiers, UInt32(cmdKey | optionKey | controlKey))
      XCTAssertEqual(c.capture.modifiers, c.pin.modifiers)
    }
    let savedOldDefault = ShortcutPreferences.migrated([
      "hotkeys": false, "captureKey": 0, "pinKey": 1, "modifiers": cmdKey | optionKey | controlKey,
    ])
    XCTAssertFalse(savedOldDefault.enabled)
    XCTAssertEqual(savedOldDefault.capture.keyCode, 1)
    XCTAssertEqual(savedOldDefault.pin.keyCode, 35)
    let invalid = ShortcutPreferences.migrated(["hotkeys": true, "captureKey": -1, "modifiers": -1])
    XCTAssertFalse(invalid.capture.valid)  // Preserve and report invalid data rather than silently replacing customization.
  }
  func testMigrationPersistsOnceAndV2OverridesStaleLegacy() throws {
    let name = "app.xdlkc.stillpin.tests.\(UUID().uuidString)"
    let d = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { d.removePersistentDomain(forName: name) }
    d.set(true, forKey: "hotkeys")
    d.set(4, forKey: "captureKey")
    d.set(5, forKey: "pinKey")
    d.set(cmdKey, forKey: "modifiers")
    let first = ShortcutPreferences.load(d)
    d.set(0, forKey: "captureKey")
    XCTAssertEqual(ShortcutPreferences.load(d), first)
    var custom = first
    custom.enabled = false
    custom.toggle = Shortcut(keyCode: 103, modifiers: UInt32(optionKey))
    ShortcutPreferences.save(custom, to: d)
    XCTAssertEqual(ShortcutPreferences.load(d), custom)
    XCTAssertNotNil(d.object(forKey: "captureKey"))  // Migration leaves the original legacy record intact.
  }
  func testRegistrationPassesUnmodifiedDefaultsAndDistinctIDs() {
    var attempted: [(Shortcut, UInt32)] = []
    var released = 0
    let h = Hotkeys(
      register: { binding, id in
        attempted.append((binding, id))
        return .success { released += 1 }
      }, reserved: { [] })
    XCTAssertNil(h.apply(.defaults))
    XCTAssertEqual(attempted.map(\.0), ShortcutConfiguration.defaults.bindings.map(\.1))
    XCTAssertEqual(attempted.map(\.1), [1, 2, 3])
    h.disable()
    XCTAssertEqual(released, 3)
    XCTAssertTrue(h.releaseHandlers.isEmpty)
  }
  func testSystemAndAppConflictRollbackWithoutChangingPreferences() {
    let original = ShortcutConfiguration.defaults
    var registered = 0
    var released = 0
    let reserved = Hotkeys(
      register: { _, _ in
        registered += 1
        return .success {}
      }, reserved: { [original.capture] })
    XCTAssertTrue(reserved.apply(original)!.contains("reserved by macOS"))
    XCTAssertEqual(registered, 0)
    let appConflict = Hotkeys(
      register: { _, id in
        if id == 2 { return .failure(OSStatus(eventHotKeyExistsErr)) }
        return .success { released += 1 }
      }, reserved: { [] })
    let result = appConflict.apply(original)!
    XCTAssertTrue(result.contains("Pin clipboard (F3)"))
    XCTAssertTrue(result.contains("saved keys are preserved"))
    XCTAssertEqual(released, 1)
    XCTAssertTrue(appConflict.releaseHandlers.isEmpty)
    XCTAssertEqual(original, .defaults)
    var duplicate = original
    duplicate.pin = duplicate.capture
    XCTAssertTrue(appConflict.apply(duplicate)!.contains("same shortcut"))
    var disabled = original
    disabled.enabled = false
    XCTAssertNil(appConflict.apply(disabled))
  }
  func testMacEditorBindingsAndUnimplementedCommands() {
    for (letter, command) in [("c", EditorCommand.copy), ("s", .save), ("t", .pin), ("z", .undo)] {
      XCTAssertEqual(EditorCommand.resolve(key(letter, modifiers: .command)), command)
    }
    XCTAssertEqual(EditorCommand.resolve(key("Z", modifiers: [.command, .shift])), .redo)
    XCTAssertEqual(EditorCommand.resolve(key("\r", code: 36)), .copyAndClose)
    XCTAssertEqual(EditorCommand.resolve(key("\u{1b}", code: 53)), .cancel)
    XCTAssertEqual(EditorCommand.resolve(key("t")), .text)
    XCTAssertNil(EditorCommand.resolve(key("s", modifiers: [.command, .shift])))  // Quick Save is not implemented.
    XCTAssertNil(EditorCommand.resolve(key("a", modifiers: .command)))
    XCTAssertNil(EditorCommand.resolve(key("b")))
    XCTAssertNil(EditorCommand.resolve(key("e")))
  }
  @MainActor func testActualEditorCopyUndoRedoAndPinCloseHandlers() throws {
    _ = NSApplication.shared
    let c = CGContext(
      data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let editor = Editor(image: c.makeImage()!)
    editor.showWindow(nil)
    let board = NSPasteboard.withUniqueName()
    editor.copyPasteboard = board
    defer {
      editor.close()
      board.releaseGlobally()
    }
    editor.canvas.marks = [Mark(tool: .cover, start: .zero, end: CGPoint(x: 50, y: 50))]
    XCTAssertTrue(editor.window!.performKeyEquivalent(with: key("z", modifiers: .command)))
    XCTAssertEqual(editor.canvas.marks.count, 0)
    XCTAssertTrue(
      editor.window!.performKeyEquivalent(with: key("z", modifiers: [.command, .shift])))
    XCTAssertEqual(editor.canvas.marks.count, 1)  // Redo restores; never clear edits.
    XCTAssertTrue(editor.window!.performKeyEquivalent(with: key("c", modifiers: .command)))
    XCTAssertNotNil(board.data(forType: .png))
    editor.canvas.keyDown(with: key("t"))
    XCTAssertEqual(editor.canvas.tool, .text)
    XCTAssertEqual(editor.toolPicker?.selectedSegment, 2)
    let previousDelegate = NSApp.delegate
    let fixtureApp = AppDelegate()
    NSApp.delegate = fixtureApp
    XCTAssertTrue(editor.window!.performKeyEquivalent(with: key("t", modifiers: .command)))
    XCTAssertEqual(fixtureApp.pins.count, 1)
    fixtureApp.closePins()
    NSApp.delegate = previousDelegate

    let pin = Pin(image: c.makeImage()!)
    pin.showWindow(nil)
    XCTAssertTrue(pin.window!.performKeyEquivalent(with: key("w", modifiers: .command)))
    XCTAssertFalse(pin.window!.isVisible)
    let escapePin = Pin(image: c.makeImage()!)
    escapePin.showWindow(nil)
    escapePin.window!.keyDown(with: key("\u{1b}", code: 53))
    XCTAssertFalse(escapePin.window!.isVisible)
    editor.canvas.keyDown(with: key("\r", code: 36))
    XCTAssertFalse(editor.window!.isVisible)
  }
  @MainActor func testNewAnnotationInvalidatesRedo() {
    let canvas = Canvas(image: CGImage.testBlank())
    canvas.marks = [Mark(tool: .box, start: .zero, end: CGPoint(x: 20, y: 20))]
    canvas.undoMark()
    XCTAssertEqual(canvas.redoMarks.count, 1)
    let w = NSWindow(
      contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = canvas
    func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    canvas.mouseDown(with: mouse(.leftMouseDown, .zero))
    canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 50, y: 50)))
    XCTAssertTrue(canvas.redoMarks.isEmpty)
    w.close()
  }
}
extension CGImage {
  fileprivate static func testBlank() -> CGImage {
    CGContext(
      data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      .makeImage()!
  }
}
