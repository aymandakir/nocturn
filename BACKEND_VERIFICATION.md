# Backend Verification: Per-App Detection and Control

Date: 2026-04-22

Scope verified:

- active audio app detection
- per-app tap/session creation
- per-app volume apply path
- per-app mute apply path
- unsupported/fallback behavior

This pass does **not** add new product features and does not expand app scope.

## What was tested

## 1) Static backend path inspection

Inspected:

- `Nocturn/Core/AudioEngine.swift`
- `Nocturn/Core/AudioTapManager.swift`
- `Nocturn/UI/AppRowView.swift`
- `Nocturn/UI/Components/VolumeSlider.swift`

Confirmed control flow:

- app detection -> `AudioEngine.detectActiveAudioPIDs()`
- app creation -> `makeAudioApp(for:)`
- tap startup -> `AudioTapManager.startTap(for:)`
- volume apply -> `AudioEngine.updateVolume` -> `AudioTapManager.setVolume`
- mute apply -> `AudioEngine.updateMute` -> `AudioTapManager.setMuted`

## 2) Build verification

Build command used:

```bash
xcodebuild -project Nocturn.xcodeproj -scheme Nocturn -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Result: build succeeds after diagnostics changes.

## 3) Runtime diagnostics added

Added logs for:

- active process detection count and PID list
- detection fallback path when CoreAudio process enumeration fails
- tap/session start success/failure per PID
- volume request attempts and apply path
- mute request attempts and apply path
- skipped apply attempts when no active tap session exists

## What succeeded

- Backend path is now observable through explicit audio logs.
- Detection fallback is honest (empty set, no fake “all running apps” fallback).
- UI control availability now depends on per-app session success, not just global runtime check.
- Volume/mute requests are blocked and logged when backend control is unavailable.

## What failed / unverified

- This pass does not include interactive end-to-end acoustic validation (listening test) in this automation context.
- Therefore, “audible per-app attenuation/mute quality” remains runtime/device dependent and should be manually validated.

## Required runtime conditions

For real per-app control in current architecture:

- macOS 14.2+ (process tap APIs)
- working CoreAudio process object enumeration
- successful tap + aggregate session startup per target PID
- microphone/audio permission path accepted by user if requested

If these conditions are not met:

- Nocturn can still show app rows (when detectable) but per-app controls show unavailable reason and are disabled.

## Current verdict

- **Active app detection:** works in code path with honest fallback behavior.
- **Per-app volume:** conditionally works only when per-app tap session is active; otherwise disabled with explicit reason.
- **Per-app mute:** same as volume path.

Nocturn currently delivers:

- real detection + real control attempts,
- but **not universal guaranteed per-app control on all runtimes/apps**.

## Manual Live Test Procedure

Use one known audio source app (Spotify, Music, or a browser tab playing audio).

1. Launch Nocturn and open the popover.
2. Open `Settings` and enable `Diagnostics Mode`.
3. Click `Refresh Audio Apps`.
4. In `Live Diagnostics`, find your source app and verify:
   - `PID` is present
   - `tapSessionStarted: true`
   - `controlAvailable: true`
   - `reason: none`
5. Go back to the app row in the popover:
   - move the volume slider
   - toggle mute
6. Confirm success indicators:
   - UI diagnostics remain `tapSessionStarted: true` and `controlAvailable: true`
   - audio behavior changes audibly for that app
   - logs show apply attempts (`Applied volume ...`, `Applied mute ...`)

Failure indicators:

- `tapSessionStarted: false` or `controlAvailable: false`
- non-empty `reason`
- logs show skipped apply attempts due to unavailable control/session

