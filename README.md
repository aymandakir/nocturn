# Nocturn

Nocturn is a lightweight macOS menu bar audio manager.

v0.1 focuses on one core job: show active audio apps and let you manage each
app's volume/mute from one place when runtime support is available.

## What Nocturn Is (v0.1)

- A stable menu bar app (`LSUIElement`) with a popover interface.
- A compact audio manager with:
  - `System Output` section
  - `Active Apps` list
  - `Settings` sheet
- Honest runtime behavior: if per-app control is unavailable, the UI says so and
  disables controls instead of pretending it works.

## What Works Today

- App launches and stays in the menu bar.
- Popover opens/closes reliably.
- Active app list is driven by CoreAudio process-object detection.
- Each app row shows:
  - app icon
  - app name
  - volume slider (when available)
  - mute toggle (when available)
- Global/system output volume slider is available.
- Settings sheet opens and launch-at-login toggle is wired.

## Not in v0.1 Scope

- EQ and effects controls
- Advanced routing UI
- HAL driver flow for general users
- “SoundSource clone” feature parity

These areas are intentionally hidden/disabled in the current product direction.

## Requirements

- macOS 14.0 (Sonoma) or later
- macOS 14.2+ for current per-app AudioTap control path
- Xcode 16+ to build from source

## Installation

Use local builds/pre-release artifacts for now.

## Building from Source

Nocturn's Xcode project is generated from `project.yml` using
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
brew install xcodegen
git clone https://github.com/aymandakir/nocturn.git
cd nocturn
xcodegen generate
xcodebuild -project Nocturn.xcodeproj -scheme Nocturn -configuration Debug build
open Nocturn.xcodeproj
```

Build and run the `Nocturn` scheme. The app appears in your menu bar with no
Dock icon.

## Planned Later (Post-v0.1)

- Harder guarantees for per-app control across more runtime combinations
- Optional advanced controls behind clear feature gates
- Production-ready packaging/signing/release pipeline

## Privacy

Nocturn never records, stores, or transmits audio. AudioTap is used purely to
transform the audio in real time for volume, mute, and EQ. No data leaves
your device.

## License

GPLv2. The CoreAudio driver component is based on
[BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) (GPLv2).