# Local Build and Test

This guide is for building and testing Nocturn locally from source.

## 1) Build prerequisites

- macOS 14.0+
- Full Xcode 16+ installed (not just Command Line Tools)
- Homebrew

## 2) Select full Xcode toolchain

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

If `xcodebuild -version` fails or points only to Command Line Tools, install full Xcode first.

## 3) Generate and build

```bash
cd /path/to/nocturn
brew install xcodegen
xcodegen generate
xcodebuild -project Nocturn.xcodeproj -scheme Nocturn -configuration Debug build
```

## 4) Run from Xcode

```bash
open Nocturn.xcodeproj
```

Then in Xcode:

1. Select scheme `Nocturn`
2. Press `Cmd+R`
3. Confirm menu bar icon appears

## 5) What to test

- Popover opens/closes from menu bar icon
- Output section renders and global slider moves
- App list renders when audio-producing apps are active
- Per-app controls:
  - slider
  - mute button
  - EQ panel expansion
- Settings sheet opens and closes
- Launch at login toggle interaction

## 6) What to expect (current beta reality)

- Audio controls are best-effort in MVP and may not provide perfect per-app isolation.
- If AudioTap is unavailable, app-level controls are disabled intentionally.
- HAL driver is experimental and not ready for general use.

