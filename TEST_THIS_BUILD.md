# Test This Build

This document explains how to open and test the local packaged build artifact:

- `Nocturn-v0.1.0-local.zip` (contains `Nocturn.app`)

If Gatekeeper blocks launch (unsigned/local build), use **right-click -> Open**.

## Open The App

1. Unzip `Nocturn-v0.1.0-local.zip`.
2. Move `Nocturn.app` to `/Applications` (optional but recommended).
3. Launch:
   - Right-click `Nocturn.app` -> `Open`
   - Confirm the security prompt.
4. Verify menu bar icon appears (No Dock icon is expected).

## What To Test

## 1) Core UI

- Click menu bar icon: popover opens.
- Click outside popover: popover closes.
- Confirm sections render:
  - Output section
  - Apps section
  - Input section (expand/collapse)
- Click gear icon: Settings sheet opens and closes.

## 2) Audio Behavior

1. Start an app producing audio (Music/Spotify/Browser tab).
2. Confirm app appears in the APPS list.
3. For that app row:
   - Move volume slider
   - Toggle mute
   - Expand EQ panel and move one or two bands
4. Observe audible behavior and whether controls are responsive.

## 3) Settings

- Toggle Launch at Login.
- Check Driver section status (experimental).
- Confirm no crash when opening/closing settings repeatedly.

## Known Limitations / Experimental Parts

- AudioTap path is currently best-effort MVP behavior, not guaranteed perfect per-app isolation in all scenarios.
- If AudioTap is unavailable on runtime/OS, controls are intentionally disabled rather than pretending to work.
- HAL driver path is experimental and not required for this local MVP test.
- Input meter is currently basic and not a calibrated meter.

