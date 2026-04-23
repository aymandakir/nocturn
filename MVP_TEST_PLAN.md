# Nocturn MVP Test Plan

This plan validates the current local MVP behavior as implemented today.

## 1) Build Steps

1. Select full Xcode developer directory:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

1. Verify the toolchain:

```bash
xcodebuild -version
```

1. Generate and build:

```bash
cd /Users/yex/nocturn
brew install xcodegen
xcodegen generate
xcodebuild -project Nocturn.xcodeproj -scheme Nocturn -configuration Debug build
```

1. Launch from Xcode:
  - `open Nocturn.xcodeproj`
  - Select scheme `Nocturn`
  - Run (`Cmd+R`)

## 2) Launch / Menu Bar Smoke Test

1. Confirm app appears in menu bar (no Dock icon expected).
2. Click status icon:
  - Popover opens.
3. Click outside popover:
  - Popover closes (`.transient` behavior).

## 3) Device Section Test

1. In popover, verify:
  - `OUTPUT` section renders.
  - Current output device name appears.
  - Global volume slider renders and moves.
2. Expand `INPUT` section:
  - Input device row renders when available.

## 4) Active App List and Audio Controls

1. Start an app producing audio (e.g. Music, browser tab, Spotify).
2. Verify app row appears in `APPS`.
3. Test controls:
  - Move per-app slider.
  - Toggle mute.
  - Expand EQ panel and move a band.
4. Expected MVP behavior:
  - On supported AudioTap runtime, controls should affect tapped stream path.
  - If AudioTap is unavailable, controls are disabled and UI shows this state.

## 5) Settings Sheet Test

1. Click gear icon.
2. Verify settings sheet opens.
3. Test:
  - Launch at login toggle changes state (or shows permission/error if blocked).
  - Driver section shows status and is clearly marked experimental.
4. Close with `Done`.

## 6) Current Known Limitations

- AudioTap control path is best-effort in MVP; strict per-app isolation is not yet guaranteed in all scenarios.
- HAL driver target/install flow is experimental and not required for local MVP usage.
- If CoreAudio process enumeration fails, app list intentionally shows no active apps (no false-positive fallback to all running apps).

