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

Global shortcuts are **disabled by default**. In Settings select distinct capture/pin keys (S, P, F6–F10), any combination of Command/Option/Control/Shift, enable and Apply. At least one modifier is required. Suggested initial combination: Control–Option–Command with S and P. Registration failure disables Stillpin's shortcuts and shows an error; it never quits another app. Some shortcuts owned by other apps that do not register with Carbon cannot be detected reliably, so choose unused combinations.

Local commands: **Esc** cancels selection, **⌘Z** undoes annotation, **⌘O** opens an image, **⌘,** opens settings, **⌘Q** quits when Stillpin is active. Text entry supports standard editing shortcuts. No Accessibility, Full Disk Access, login item or background clipboard permissions are requested.

## Privacy

All capture and image processing happens locally. No network code, telemetry, uploads, screen history or automatic clipboard monitoring. Saving uses a user-selected location; Copy deliberately replaces the clipboard with a PNG. No real screenshots, clipboard data, credentials or generated builds belong in git. Closing the app discards editors and pins.

## Coordinate and rendering behavior

Selection uses AppKit's global bottom-left coordinate space, including displays left of or above the primary screen. Each ScreenCaptureKit frame is cropped in its own top-left pixel coordinate space. Composition uses the highest selected display scale; lower-density areas are resampled. Black gaps represent physical empty space between display rectangles. Export retains pixels rather than the editor's zoom. Synthetic tests cover negative origins, vertical arrangement, mixed density, orientation and irreversible flattened cover output.

## Current scope and limitations

Implemented: menu bar app; opt-in configurable registered global hotkeys; frozen region selection; multi-display composition; basic arrow/box/text/opaque cover and undo; flattened PNG copy/save; screenshot and clipboard pins; per-pin close, drag, resize, opacity; hide/show/close all; explicit permission onboarding; Universal ZIP/DMG scripts and CI.

Not included: OCR, window/element auto-detection, scrolling capture, magnifier/color picker, capture history, persistence across restarts, redo, editing existing marks, color/font/line-width controls, pixelation, timed capture, launch at login, update service, notarization or App Store packaging. Text is orange on a dark backdrop. Cover should have a generous margin around sensitive text. The preview and source remain editable in memory; share the exported PNG, not the editor.

Real capture requires user-approved Screen Recording. Synthetic geometry and window tests do not prove real multi-monitor capture. See [VALIDATION.md](VALIDATION.md) for actual execution evidence and outstanding physical-device checks. Capture can fail on protected content, display reconfiguration, permissions, locked sessions or unavailable WindowServer. Pins are not guaranteed to overlay secure/system UI or every full-screen app. Sequential snapshots can differ in time across displays. No runtime Apple Silicon or macOS 13 test is implied by cross-compiling.

## Development

`Package.swift` is the project; open it in Xcode or edit the source directly. The packaged app has a stable bundle identifier and LSUIElement menu bar behavior. Use `open dist/Stillpin.app --args --practice` for a synthetic editor. Scripts use workspace-local compiler caches. AppKit UI work runs on the main actor; capture frames arrive on a private queue with a lock-protected single continuation and timeout. There are no external package dependencies.

Apple API references: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [screen capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos). Workflow inspiration: [Snipaste](https://www.snipaste.com/). Neither affiliation nor feature parity is claimed.
