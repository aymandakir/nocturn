# Nocturn v0.1 Architecture

This document describes the current product-scoped architecture after the v0.1 pivot.

## 1) App Shell

- Entry point: `Nocturn/NocturnApp.swift`
- Lifecycle + menu bar wiring: `Nocturn/AppDelegate.swift`
- Responsibilities:
  - Create `NSStatusItem`
  - Show/hide transient popover
  - Inject runtime state into SwiftUI

## 2) Audio App Detection

- Core module: `Nocturn/Core/AudioEngine.swift`
- Device discovery: `Nocturn/Core/DeviceManager.swift`
- Detection approach:
  - Query CoreAudio process object list
  - Build `AudioApp` entries from active PIDs
  - Poll periodically and apply grace-period removal
- Honesty rule:
  - If process enumeration fails, return no active app entries
  - Never fallback to “all running apps”

## 3) Per-App Control Layer

- Per-app control implementation:
  - `Nocturn/Core/AudioTapManager.swift`
  - `Nocturn/Core/AudioEngine.swift` (`updateVolume`, `updateMute`)
- UI control surface:
  - `Nocturn/UI/AppRowView.swift`
  - `Nocturn/UI/Components/VolumeSlider.swift`
- Scope:
  - Per-app volume slider
  - Per-app mute toggle
  - No EQ/routing/driver controls in v0.1

## 4) Settings and Persistence

- Settings UI: `Nocturn/UI/SettingsView.swift`
- Persisted state:
  - `nocturn.volume.<bundleID>`
  - `nocturn.mute.<bundleID>`
- Launch-at-login:
  - `Nocturn/Utilities/Permissions.swift`

## 5) Fallback Behavior

- Runtime support state exposed via `AudioEngine.tapAvailable`.
- If per-app control is unavailable:
  - App rows remain visible
  - Per-app controls are disabled
  - UI shows explicit “unavailable” messaging
- This avoids false claims and keeps the app stable.

