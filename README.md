# Stillpin

A local, native macOS screenshot and floating-image tool. macOS 13+, Intel and Apple Silicon. Written in Swift/AppKit using Apple's ScreenCaptureKit. Stillpin has its own identity and artwork; it is inspired by the capture → annotate → pin workflow, not a full Snipaste clone.

## Build and run

Requires Xcode 15+ (Swift 5.9+) and its command line tools; no third-party dependencies or accounts.

```sh
scripts/test.sh
scripts/build.sh
open dist/Stillpin.app
scripts/dmg.sh # optional
```

The build produces `dist/Stillpin-universal.zip`, an app bundle and SHA-256 checksums. The optional DMG contains the app and an Applications shortcut. Nothing is installed automatically. The binary includes both `arm64` and `x86_64`; `lipo` verifies both during packaging. CI tests and builds the same scripts and attaches ZIP/DMG artifacts to each run.

**Signing:** the app is ad-hoc signed, without an Apple Developer membership or notarization. Gatekeeper may prevent opening an unnotarized download. Review the source and use macOS's per-app Open Anyway option if you trust the build. Do not disable Gatekeeper or other system security. Stable Developer ID signing/notarization is future distribution work. Moving or rebuilding an ad-hoc app may require re-approving Screen Recording.

## Use

1. Launch the app. Its pin icon appears in the menu bar; Settings opens on first launch.
2. For capture, choose **Request Screen Recording** in Settings. macOS asks permission for **Stillpin** (`app.xdlkc.stillpin`). Approve it yourself in System Settings → Privacy & Security → Screen Recording (called Screen & System Audio Recording on newer systems). Relaunch if macOS requests it. This app captures no audio.
3. Choose **Capture Region…**. Drag across the display or display boundary; release opens the annotation editor. **Escape** cancels and removes all overlays. Displays are captured sequentially, then frozen during selection.
4. Select **Arrow**, **Box**, **Text**, or **Cover**. Drag to draw; Text opens an entry dialog. Cover is solid black. **Undo** or **⌘Z** removes the most recent annotation. Use the scroll view and trackpad pinch to navigate large images.
5. **Copy**, **Save PNG…**, and **Pin** all use the same flattened image. Covered pixels are replaced in exported PNG data; no annotation layers or original image are embedded. The source image remains in the editor's memory for Undo until you close it.
6. **Pin Clipboard Image** reads the clipboard only when invoked. **Open Image…** opens a local PNG/JPEG/TIFF in the editor. **Synthetic Practice Image** lets you try the editor without screen access or clipboard data.
7. Drag a pin's title bar to move it; drag its edges/corners to resize with its image aspect ratio. Right-click the image for opacity (20–100%) or Close Pin. Use **Hide / Show All Pins** or **Close All Pins** from the menu bar. Pins float above normal windows and join Spaces, subject to macOS window rules.

## Shortcuts

The defaults now follow Snipaste's documented core workflow:

| Context | Shortcut | Stillpin action |
| --- | --- | --- |
| Global | F1 | Capture region |
| Global | F3 | Pin clipboard image |
| Global | Shift+F3 | Hide/show all pins |
| Editor | ⌘C / Enter | Copy flattened PNG / copy and close |
| Editor | ⌘S | Save PNG dialog |
| Editor | ⌘T | Pin the annotated image |
| Editor | ⌘Z / ⌘⇧Z | Undo / redo |
| Editor | T / Esc | Select Text / close and cancel editor |
| Selection overlay | Esc | Cancel selection and remove overlays |
| Focused pin | ⌘W / Esc | Close this pin |

New/untouched installations enable the three global defaults. [Apple keyboards](https://support.apple.com/en-us/102650) may require **Fn+F1 / Fn+F3 / Fn+Shift+F3** to send function-key events instead of brightness/Mission Control actions; Stillpin does not change this system setting. On conflict, choose unused keys in Settings. Each global action has its own key and modifiers, and the menu displays its active assignment. You can disable all global shortcuts or explicitly choose **Restore Snipaste Defaults**.

**Existing settings are preserved.** Version 0.1.0 saved shortcut fields only when the user applied them (or explicitly disabled a failed configuration). Any persisted legacy keys are treated conservatively as explicit user intent, even if they equal the old S/P suggestions. Their enabled state, physical key codes and modifiers migrate once to a versioned per-action record. An untouched installation with no shortcut fields gets F1/F3/Shift+F3. Migration never silently overwrites saved custom bindings; use Restore Snipaste Defaults to opt in. Invalid or conflicting settings remain saved and are shown inactive, not silently replaced.

Before registration Stillpin checks enabled macOS symbolic hotkeys, then requests exclusive Carbon registration. Duplicate assignments or any registration failure roll back the entire attempt, show the failing action/key and error, and preserve the saved configuration. Other applications and system shortcuts are never changed. Software that intercepts keys outside Carbon, Fn/media handling and hardware remapping cannot be exhaustively detected; actual physical-key testing remains necessary.

The official [Getting Started](https://github.com/Snipaste/feedback/wiki/Getting-Started) page documents the global function keys, while [Key Bindings](https://github.com/Snipaste/feedback/wiki/Key-Bindings) explicitly maps its Windows/Linux Ctrl commands to **Cmd on macOS**. The Mac-specific [v2.4 Beta changelog](https://github.com/Snipaste/feedback/wiki/Changelog#v24-beta-mac) specifies **⌘⇧Z for redo**, taking precedence over the generic table's clear-all chord. Stillpin never uses ⌘⇧Z to delete all marks.

⌘O opens an image, ⌘, opens settings and ⌘Q quits while Stillpin is active. Text entry retains standard macOS editing shortcuts. Quick Save (⌘⇧S), full-screen selection (⌘A), toolbar toggle (Space), last-region/history shortcuts, pencil (B), eraser (E), and pin rotation/flipping/replacement remain unimplemented; no binding claims otherwise.

## Privacy

All capture and image processing happens locally. No network code, telemetry, uploads, screen history or automatic clipboard monitoring. Saving uses a user-selected location; Copy deliberately replaces the clipboard with a PNG. No real screenshots, clipboard data, credentials or generated builds belong in git. Closing the app discards editors and pins.

## Coordinate and rendering behavior

Selection uses AppKit's global bottom-left coordinate space, including displays left of or above the primary screen. Each ScreenCaptureKit frame is cropped in its own top-left pixel coordinate space. Composition uses the highest selected display scale; lower-density areas are resampled. Black gaps represent physical empty space between display rectangles. Export retains pixels rather than the editor's zoom. Synthetic tests cover negative origins, vertical arrangement, mixed density, orientation and irreversible flattened cover output.

## Current scope and limitations

Implemented: menu bar app; configurable registered global hotkeys; frozen region selection; multi-display composition; basic arrow/box/text/opaque cover and undo/redo; flattened PNG copy/save; screenshot and clipboard pins; per-pin close, drag, resize, opacity; hide/show/close all; explicit permission onboarding; Universal ZIP/DMG scripts and CI.

Not included: OCR, window/element auto-detection, scrolling capture, magnifier/color picker, capture history, persistence across restarts, editing existing marks, color/font/line-width controls, pixelation, timed capture, launch at login, update service, notarization or App Store packaging. Text is orange on a dark backdrop. Cover should have a generous margin around sensitive text. The preview and source remain editable in memory; share the exported PNG, not the editor.

Real capture requires user-approved Screen Recording. Synthetic geometry and window tests do not prove real multi-monitor capture. See [VALIDATION.md](VALIDATION.md) for actual execution evidence and outstanding physical-device checks. Capture can fail on protected content, display reconfiguration, permissions, locked sessions or unavailable WindowServer. Pins are not guaranteed to overlay secure/system UI or every full-screen app. Sequential snapshots can differ in time across displays. No runtime Apple Silicon or macOS 13 test is implied by cross-compiling.

## Development

`Package.swift` is the project; open it in Xcode or edit the source directly. The packaged app has a stable bundle identifier and LSUIElement menu bar behavior. Use `open dist/Stillpin.app --args --practice` for a synthetic editor. Scripts use workspace-local compiler caches. AppKit UI work runs on the main actor; capture frames arrive on a private queue with a lock-protected single continuation and timeout. There are no external package dependencies.

Apple API references: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [screen capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos). Workflow inspiration: [Snipaste](https://www.snipaste.com/). Neither affiliation nor feature parity is claimed.

After manually approving Stillpin's Screen Recording permission, developers can run `open -n -W --stdout "$PWD/.build/real-capture.log" dist/Stillpin.app --args --verify-capture` from the project folder. This explicit check covers one display with an opaque synthetic white window, captures an inset region through ScreenCaptureKit, then verifies cover/copy (isolated pasteboard)/local PNG/pin/cancel behavior and exits. It never requests or grants permission and prints `STILLPIN_CAPTURE_PENDING` if approval is absent. Only the synthetic cropped fixture may be saved to a `StillpinVerification` directory under the app’s temporary directory (exact path is printed in the log); CI never runs this permission-dependent check. It does not replace physical mixed-display or manual pointer/shortcut testing.

For a registration-only check, run `open -n -W --stdout "$PWD/.build/hotkey-registration.log" dist/Stillpin.app --args --verify-hotkeys`. It checks system reservations and attempts exclusive F1/F3/Shift+F3 registration, immediately unregisters, prints PASS or the exact conflict, and exits. It never fires keys or runs capture/clipboard actions. A registration PASS is not physical-key validation.
