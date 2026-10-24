# Validation record

## Local checks (2026-10-24)

Host: connected Intel Mac; Xcode Swift 6.3 toolchain; macOS 26. Package minimum: macOS 13. Builds are local and ad-hoc signed, never notarized.

10 XCTest cases passed with zero failures using only generated images and synthetic windows:

- Negative display origin and Retina pixel crop.
- Display above primary and vertical coordinate conversion.
- Mixed 1×/2× display boundary composition and pixel colors.
- Original/export vertical orientation.
- Opaque black Cover pixels in flattened image and PNG decode; undo restoration.
- Canvas mouse down/drag/up → Cover → Copy to isolated named pasteboard → PNG write/read → clipboard-image pin, with covered pixels verified again.
- Native editor undo and pin open/resize/opacity/hide/show/close lifecycle.
- Multiple pins hide/show/close-all.
- Escape closes all synthetic selection overlays and clears state.
- Duplicate shortcut rejection and clean disable (does not register a shortcut over an existing tool).

Tests touch no real clipboard and capture no real screen. The WindowServer-backed tests run outside the filesystem sandbox; the sandbox's virtual display constrains native window sizing and caused a resize assertion failure there. The same test passes against the normal WindowServer. Native-control offscreen caching produces black/incomplete snapshots, so those are not visual acceptance evidence. Custom canvas pixels were inspected; system-control visual review remains manual.

## Delivery checks

Use the following against a packaged app:

```sh
lipo dist/Stillpin.app/Contents/MacOS/Stillpin -verify_arch arm64 x86_64
codesign --verify --strict dist/Stillpin.app
codesign -dv --verbose=2 dist/Stillpin.app 2>&1
scripts/dmg.sh
```

The CI workflow checks tests, builds Universal ZIP and DMG, and uploads artifacts named with the exact source commit. Local smoke mode (`dist/Stillpin.app/Contents/MacOS/Stillpin --smoke-test`) starts the actual menu app, opens settings and a synthetic editor, prints PASS/FAIL and terminates itself; it makes no capture/clipboard/permission requests and does not enable shortcuts. It is not a substitute for manual capture testing.

## Outstanding user/device checks

**Screen Recording is not granted or assumed. No real screenshot capture is claimed to have passed.** The build can be exercised without it using Open Image or Synthetic Practice Image. For a real capture test, the user must explicitly request and approve **Stillpin** / **app.xdlkc.stillpin** in System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording), then relaunch if requested by macOS. This is pending user action, not a denied action. No Accessibility, Full Disk Access or startup permission is needed.

After approval, manually verify:

1. Drag a region over a non-sensitive test window; compare pixel edges on a Retina screen.
2. Capture across actual 1×/2× monitors, including left/above primary layouts; check rotated displays and display gaps. Hotplug during capture should fail safely rather than produce incomplete display sets.
3. Escape before release and confirm every screen is interactive again.
4. Text dialog, Undo, Copy and Save PNG panel; open exported file and inspect all annotation types and cover margins.
5. Pin screenshot and a copied synthetic image; drag/resize, change all opacity steps, close one, hide/show all and close all; check Spaces/fullscreen behavior.
6. Choose unused shortcuts, enable, capture/pin from another app; verify conflict messaging. Global shortcut registration/invocation against other running applications is not yet verified.
7. Gatekeeper distribution flow for the unsigned-by-Developer-ID, unnotarized download; no security policies should be disabled.

Apple Silicon execution, macOS 13 execution, real physical multi-display capture and real permission prompt behavior remain unverified even when Universal compilation succeeds. Screenshots of the user's environment must never be committed to the repository.

## Executed package verification

- Final local run: 10 tests, 0 failures (2026-10-24 13:11 UTC).
- Actual packaged app: `STILLPIN_SMOKE_PASS menu settings editor`.
- `lipo -archs`: `x86_64 arm64`; `-verify_arch arm64 x86_64` succeeded.
- Mach-O `LC_BUILD_VERSION`: minimum macOS 13.0.
- `codesign --verify --strict`: passed. Signature reports `adhoc`, identifier `app.xdlkc.stillpin`, no TeamIdentifier. No notarization performed.
- Universal ZIP and DMG generated successfully; archive checksums are next to the outputs in `dist/SHA256SUMS.txt`. Outputs are deliberately excluded from git and are also produced as CI artifacts.
