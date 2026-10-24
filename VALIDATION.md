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

Physical Apple Silicon capture, macOS 13 execution, real physical multi-display capture and real permission prompt behavior remain unverified. Synthetic runtime tests on the CI Apple Silicon runner are separately recorded below. Screenshots of the user's environment must never be committed to the repository.

## Executed package verification

- Final local run: 10 tests, 0 failures (2026-10-24 05:11 UTC).
- Actual packaged app: `STILLPIN_SMOKE_PASS menu settings editor`.
- `lipo -archs`: `x86_64 arm64`; `-verify_arch arm64 x86_64` succeeded.
- Mach-O `LC_BUILD_VERSION`: minimum macOS 13.0.
- `codesign --verify --strict`: passed. Signature reports `adhoc`, identifier `app.xdlkc.stillpin`, no TeamIdentifier. No notarization performed.
- Universal ZIP and DMG generated successfully; archive checksums are next to the outputs in `dist/SHA256SUMS.txt`. Outputs are deliberately excluded from git and are also produced as CI artifacts.

## Permission-gated real-capture verifier

An explicit `--verify-capture` developer mode is available and is never run in CI. Launch it through LaunchServices as documented in README so TCC identifies Stillpin, not a shell host. It checks existing approval before any capture; if approved, it covers one display with an opaque white synthetic window and requires every captured crop pixel to be white before saving any PNG. It then verifies local region capture, flattened cover, isolated clipboard round trip, PNG write/read, pins, opacity, visibility and Escape cleanup. It cannot test physical mixed-DPI layouts or manual pointer interaction by itself.

Executed locally via LaunchServices after user authorization: `STILLPIN_CAPTURE_PENDING`. Stillpin has not received the actual macOS grant, so no real screen was captured. The native UI automation surface is unavailable in this environment; the user must click Request Screen Recording in Stillpin and approve only Stillpin in System Settings. This is pending manual UI action, not an automatic approval denial. Do not give Terminal, Codex or any other application Screen Recording as a workaround.

Initial commit `1f5c127dc940ae2d12d72fbf9562f16c01bc5791` passed CI run [40065345784](https://github.com/xdlkc/stillpin/actions/runs/40065345784). The follow-up verifier commit must have its own successful CI run; no older run is evidence for a newer commit.


## Verified implementation CI and downloaded packages

Implementation commit `adc758fa86fcfd904db26ffcda04b293ebb68fae` passed [run 40065731942](https://github.com/xdlkc/stillpin/actions/runs/40065731942). The runner image was `macos-15-arm64`: 10 synthetic tests passed with no failures, then the actual app printed `STILLPIN_SMOKE_PASS menu settings editor`. This adds Apple Silicon synthetic runtime evidence to the local Intel runtime checks; it does not demonstrate physical Apple Silicon capture.

The exact run's Universal ZIP/DMG artifacts were downloaded into the ignored build directory. Both SHA-256 checksums matched the run's manifest. The ZIP's extracted app passed strict signature verification and `lipo -verify_arch arm64 x86_64`, and identified as `app.xdlkc.stillpin` with an ad-hoc signature and no TeamIdentifier. A documentation-only follow-up commit records this evidence; its own CI result is reported with delivery.

The permission blocker is specifically unavailable native macOS UI control in the active tooling. No password or Touch ID was requested, and the System Settings list could not be inspected. The user has already authorized granting Stillpin access; that consent must still be applied in normal macOS UI. Minimum action: Stillpin menu bar → Settings & Permissions… → Request Screen Recording, then approve only Stillpin in the system prompt/settings. No repeated consent request is needed. Current app bundle is `/Users/lkc/Documents/Codex/2026-10-24/task-3/dist/Stillpin.app`.
