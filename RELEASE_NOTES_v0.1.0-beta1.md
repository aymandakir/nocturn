# Nocturn v0.1.0-beta1 (Pre-release)

This is an **early beta** intended for local testing and feedback.

## What works in this beta

- Menu bar app launches without a Dock icon (`LSUIElement` behavior)
- Status item opens/closes the popover
- Output/input sections render current device information
- Active app list UI renders from CoreAudio process-object detection
- Settings sheet opens and launch-at-login toggle is wired
- AudioTap-based controls (volume/mute/EQ path) run in a safety-first, best-effort mode on supported runtime

## Warnings and limitations

- This pre-release is unsigned/not notarized. macOS may show Gatekeeper warnings.
- Per-app audio control is **experimental** and may not be perfect isolation in all scenarios.
- If AudioTap is unavailable at runtime, app-level controls are intentionally disabled instead of pretending to work.
- HAL driver (`NocturnDriver`) is experimental and **not ready for general use**.
- Driver install/uninstall UI exists but should be treated as non-final.

## Requirements

- macOS 14.0+ (Sonoma)
- macOS 14.2+ recommended for AudioTap path
- Xcode 16+ only if building from source

## Installation note for unsigned artifact

When opening the `.app` from this pre-release:

1. Right-click `Nocturn.app`
2. Click `Open`
3. Confirm the security prompt

