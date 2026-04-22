# Nocturn

> Free, open-source macOS audio control. Per-app volume, device routing,
> and EQ — right from your menu bar.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square)
![License GPLv2](https://img.shields.io/badge/license-GPLv2-blue?style=flat-square)
![Build](https://github.com/aymandakir/nocturn/actions/workflows/build.yml/badge.svg)

Nocturn is the free alternative to SoundSource. It lives in your menu bar
and gives you independent volume control, output device routing, and EQ
for every app playing audio on your Mac — at zero cost.

## Features

- Per-app volume control (with up to 150% boost when the HAL driver is installed)
- Route individual apps to different audio outputs simultaneously
- 5-band EQ per app with presets (Flat, Bass Boost, Vocal Clarity, Custom)
- Input device picker and microphone level indicator
- Per-app mute
- Launch at login
- Completely free and open source (GPLv2)

## Requirements

- macOS 14.0 (Sonoma) or later
- macOS 14.2+ recommended (enables AudioTap API for zero-install operation)
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
brew install xcodegen
git clone https://github.com/aymandakir/nocturn.git
cd nocturn
xcodegen generate
open Nocturn.xcodeproj
```

Build and run the `Nocturn` scheme. The app appears in your menu bar (it has
no Dock icon — `LSUIElement` is `YES`).

## How It Works

On macOS 14.2+, Nocturn uses Apple's **AudioTap API**
(`CATapDescription` + `AudioHardwareCreateProcessTap`) to intercept per-process
audio with no additional installation. Each active app gets its own
`AVAudioEngine` subgraph:

```
[CATap input] → [AVAudioUnitEQ] → [Gain/Mixer] → [chosen output device]
```

For macOS 14.0–14.1, or to unlock volume boost above 100%, Nocturn can install
a **CoreAudio HAL plugin** (a virtual audio device named `Nocturn`) via the
Settings panel. The driver uses XPC to receive per-PID volume commands from the
app.

## Privacy

Nocturn never records, stores, or transmits audio. AudioTap is used purely to
transform the audio in real time for volume, mute, and EQ. No data leaves
your device.

## License

GPLv2. The CoreAudio driver component is based on
[BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) (GPLv2).

## Acknowledgments

Inspired by [SoundSource](https://rogueamoeba.com/soundsource/) by Rogue Amoeba.
