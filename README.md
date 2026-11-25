# Stillpin

English | [简体中文](./README.zh-CN.md)

**Stillpin** is a local-first, native macOS region capture, annotation, and floating image pin utility built with Swift, AppKit, and Apple's ScreenCaptureKit (`macOS 13+`, Universal `arm64` + `x86_64`). It has its own identity and artwork, inspired by the capture → annotate → pin workflow rather than attempting full Snipaste parity.

- **Zero dependencies & 100% local**: No network code, telemetry, uploads, capture history, or background clipboard monitoring. Closing the app discards all editors and pins.
- **Irreversible flattened redaction**: Copy, Save PNG, and Pin export the same flattened bitmap—covered regions replace pixels directly with no hidden original layer embedded.
- **Familiar macOS shortcuts**: Ships with `F1` (capture region), `F3` (pin clipboard image), and `Shift+F3` (hide/show pins), plus `⌘Z` / `⌘⇧Z` undo/redo in the editor, while preserving any custom user bindings across upgrades.

## Quick Start & Build

Requires Xcode 15+ (Swift 5.9+) and Command Line Tools; no third-party packages or accounts.

```bash
scripts/test.sh
scripts/build.sh
open dist/Stillpin.app
scripts/dmg.sh # optional
```

`scripts/build.sh` produces a universal (`arm64` + `x86_64`) app bundle, `dist/Stillpin-universal.zip`, and SHA-256 checksums (`lipo` verifies both architectures). The app is ad-hoc signed without Apple notarization; review the source and use macOS's per-app **Open Anyway** option if Gatekeeper blocks first launch. Moving or rebuilding an ad-hoc app may require re-approving Screen Recording.

## Core Workflow

1. Launch Stillpin—its pin icon appears in the menu bar and Settings opens on first run.
2. Click **Request Screen Recording** in Settings and approve **Stillpin** (`app.xdlkc.stillpin`) in System Settings → Privacy & Security → Screen Recording (no audio is captured).
3. Trigger **Capture Region…** (`F1`), drag across any display or display boundary, and release to open the annotation editor (`Esc` cancels).
4. Annotate with **Arrow**, **Box**, **Text**, or opaque **Cover** (`⌘Z` / `⌘⇧Z` for undo/redo), then **Copy** (`⌘C` / `Enter`), **Save PNG…** (`⌘S`), or **Pin** (`⌘T`).
5. Use **Pin Clipboard Image** (`F3`) to pin clipboard images on demand, **Open Image…** (`⌘O`) for local PNG/JPEG/TIFF files, or **Synthetic Practice Image** to test without screen permission.
6. Drag a pin's title bar to move, drag edges/corners to resize proportionally, and right-click for opacity (`20–100%`) or closing.

## Shortcuts

| Context | Shortcut | Action |
| --- | --- | --- |
| Global | `F1` | Capture region |
| Global | `F3` | Pin clipboard image |
| Global | `Shift+F3` | Hide / show all pins |
| Editor | `⌘C` / `Enter` | Copy flattened PNG / copy and close |
| Editor | `⌘S` | Save PNG dialog |
| Editor | `⌘T` | Pin annotated image |
| Editor | `⌘Z` / `⌘⇧Z` | Undo / redo |
| Editor | `T` / `Esc` | Select Text tool / cancel and close |
| Selection overlay | `Esc` | Cancel selection and remove overlays |
| Focused pin | `⌘W` / `Esc` | Close active pin |

[Apple keyboards](https://support.apple.com/en-us/102650) may require `Fn+F1` / `Fn+F3` / `Fn+Shift+F3` unless standard function keys are enabled. Stillpin checks macOS symbolic hotkey reservations before exclusive Carbon registration and rolls back atomically on conflict without altering system or other app shortcuts. Existing custom settings are preserved on upgrade; use **Restore Snipaste Defaults** in Settings to reset.

## Architecture

```text
stillpin/
├── Package.swift                      # SwiftPM manifest (macOS 13+, zero external deps)
├── Resources/Info.plist               # App bundle metadata & LSUIElement config
├── Sources/Stillpin/
│   ├── Main.swift                     # Entry point & CLI verification flags
│   ├── App.swift                      # Menu bar controller, settings & permission onboarding
│   ├── Capture.swift                  # ScreenCaptureKit multi-display capture & coordinate mapping
│   ├── Imaging.swift                  # Annotation model, flattened PNG rendering & cover redaction
│   ├── Windows.swift                  # Selection overlay, annotation editor & floating pin windows
│   ├── Shortcuts.swift                # Carbon global hotkey registration & legacy migration
│   └── CaptureVerification.swift      # Explicit permission-gated synthetic capture check
├── Tests/StillpinTests/               # Geometry, rendering, redaction & shortcut regression tests
├── scripts/                           # test.sh, build.sh (universal), dmg.sh, icon.swift
├── PLAN.md                            # Scope & implementation notes
└── VALIDATION.md                      # Verification evidence & physical-device checklist
```

## Scope & Limitations

- **Included**: Menu bar app; configurable global hotkeys; frozen multi-display region capture with mixed-DPI composition; arrow/box/text/opaque cover + undo/redo; flattened PNG copy/save; screenshot & clipboard floating pins with resize, opacity, and hide/show/close all; Universal ZIP/DMG packaging and GitHub Actions CI.
- **Not included**: OCR, window/element auto-detection, scrolling capture, color picker, capture history, persistence across restarts, editing existing marks, color/font/stroke pickers, pixelation, timed capture, launch at login, auto-update, or Apple notarization.
- See [`VALIDATION.md`](./VALIDATION.md) for actual test evidence and outstanding physical-device checks.

## Verification

```bash
scripts/test.sh

# Optional: verify real ScreenCaptureKit capture after manually granting Screen Recording
open -n -W --stdout "$PWD/.build/real-capture.log" dist/Stillpin.app --args --verify-capture

# Optional: verify Carbon global hotkey registration without firing actions
open -n -W --stdout "$PWD/.build/hotkey-registration.log" dist/Stillpin.app --args --verify-hotkeys
```
