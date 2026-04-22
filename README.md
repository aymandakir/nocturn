# Nocturn

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square)
![License GPLv2](https://img.shields.io/badge/license-GPLv2-blue?style=flat-square)
![Build](https://github.com/aymandakir/nocturn/actions/workflows/build.yml/badge.svg)

Nocturn is a native macOS menu bar app for audio controls.  
This repository is currently in MVP development; some features are intentionally
best-effort or experimental.

## Current MVP Status (v0.1.x)

Known working app shell behavior:

- Menu bar app launches (`LSUIElement`) with status item icon
- Popover opens/closes from the status item
- Output and input sections render device information
- Active app list UI renders from detected CoreAudio process objects
- Settings sheet opens and launch-at-login toggle is wired

Audio controls status:

- On macOS 14.2+ with AudioTap available, Nocturn runs a tap-based processing path
  (volume/mute/EQ controls are best-effort and safety-first).
- If AudioTap is unavailable (older runtime/unsupported state), app controls are
  shown as disabled and app remains usable without crashing.
- App does **not** fall back to listing all running apps as audio sources when
  CoreAudio process enumeration fails.

## Requirements

- macOS 14.0 (Sonoma) or later
- macOS 14.2+ for AudioTap processing path
- Xcode 16+ to build from source

## Installation

Download the latest release from the
[Releases page](https://github.com/aymandakir/nocturn/releases).

Homebrew cask (coming soon):

```bash
brew install --cask nocturn
```

## Building from Source

Nocturn's Xcode project is generated from [`project.yml`](project.yml) using
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

Build and run the `Nocturn` scheme. The app appears in your menu bar (it has
no Dock icon — `LSUIElement` is `YES`).

## Experimental / Planned

- CoreAudio HAL driver target (`NocturnDriver`) is currently experimental.
- Driver install/uninstall UI is present but should be treated as non-final.
- Strict per-app isolation guarantees are planned to be hardened in future
  driver-backed iterations.

## Notes on AudioTap in Current MVP

- Current tap path prioritizes safe behavior (avoid duplicate audio layering).
- Controls are best-effort post-processing in MVP, not a final claim of perfect
  per-app isolation in all cases.

## Privacy

Nocturn never records, stores, or transmits audio. AudioTap is used purely to
transform the audio in real time for volume, mute, and EQ. No data leaves
your device.

## License

GPLv2. The CoreAudio driver component is based on
[BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) (GPLv2).

## Acknowledgments

Inspired by [SoundSource](https://rogueamoeba.com/soundsource/) by Rogue Amoeba.
