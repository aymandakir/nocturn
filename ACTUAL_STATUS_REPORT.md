# Nocturn Actual Status Report (Strict Audit)

Date: 2026-04-22  
Repository audited: `https://github.com/aymandakir/nocturn`  
Audit mode: read-only (no implementation changes), skeptical classification

## Audit Constraints / Evidence Quality

- I inspected the current repository files directly (`project.yml`, app/core/UI/driver code, tests, workflow, plist/entitlements, Xcode scheme/project files).
- I attempted a local build probe, but compile could not be verified in this environment because `xcodebuild` is unavailable (active dev dir is CLT, not full Xcode).
- Therefore:
  - **Static code/config issues are high confidence**.
  - **Runtime behavior claims are unverified unless clearly implemented and coherent**.

## Executive Truth

- The repo is **not a cleanly shippable “first downloadable test version” yet**.
- Core app scaffolding is real and substantial, but several critical pieces are either placeholder or likely broken:
  - app entitlements are effectively empty,
  - driver target is mostly scaffold/stub and driver Info.plist is not plugin-ready,
  - release workflow has high-risk signing/export assumptions,
  - AudioTap strategy is ambitious but not proven correct end-to-end and has likely behavioral flaws.

---

## 1) Feature-by-Feature Classification

### App target (menu bar app, popover, core UI shell)

**Bucket: PARTIAL IMPLEMENTATION**

- Implemented:
  - `NSStatusItem` icon and transient `NSPopover` (`AppDelegate.swift`).
  - Main popover sections + settings sheet (`MenuBarView.swift`, `SettingsView.swift`).
  - `LSUIElement` is set in `Info.plist`.
- Missing/weak:
  - Global output is displayed but not a picker menu; input section lacks real input picker.
  - Input level is hardcoded (`ProgressView(value: 0.35)`).
  - Some UI behavior is present but not deeply wired to real audio state.

### AudioTap integration

**Bucket: LIKELY BROKEN / UNVERIFIED**

- Implemented in code:
  - `CATapDescription` + `AudioHardwareCreateProcessTap` + aggregate device creation in `AudioTapManager.swift`.
- High-risk issues:
  - Entitlement file is empty (`Nocturn/Nocturn.entitlements`), so tap entitlement is not actually present.
  - The chain appears to process a tapped stream and output it, but source mute behavior is set to `.unmuted`; this risks duplicate audio rather than true per-app control.
  - API usage and aggregate tap dictionary keys may compile only with specific SDK symbols; runtime validity is unproven.

### Per-app volume control

**Bucket: PARTIAL IMPLEMENTATION**

- UI and state update paths are present (`VolumeSlider`, `AudioEngine.updateVolume`, tap manager volume set).
- True per-app attenuation depends on AudioTap path correctness; currently unverified and likely flawed due to unmuted source duplication risk.

### Per-app output routing

**Bucket: PARTIAL IMPLEMENTATION**

- UI picker exists (`DevicePickerView`) and writes per-app `outputDeviceUID`.
- Routing implementation applies output device to AVAudioEngine output unit in session, not via `AVAudioApplication(processIdentifier:)`.
- This is a plausible processing-path route, but not verified as robust per-app system routing.

### EQ / effects

**Bucket: PARTIAL IMPLEMENTATION**

- EQ presets/sliders and AVAudioUnitEQ configuration exist (`EffectsView`, `EffectsChain`).
- Effectiveness depends on tap chain correctness; no evidence of validated audible behavior.

### SwiftData / UserDefaults persistence

**Bucket: PARTIAL IMPLEMENTATION**

- UserDefaults persistence is real for volume/mute/output/EQ payload.
- SwiftData model/store exists (`StoredEQPreset` + `NocturnDataStore` upsert).
- Gap: restore path currently reads from UserDefaults only; SwiftData is written but not used as source-of-truth in restore.

### Launch at login

**Bucket: PARTIAL IMPLEMENTATION**

- `SMAppService.mainApp.register()/unregister()` wired in settings.
- No deep verification of packaging/signing setup for reliable behavior in distributed builds.

### Global shortcut

**Bucket: PARTIAL IMPLEMENTATION**

- Global monitor exists (`NSEvent.addGlobalMonitorForEvents`) with default Option+Command+N.
- Not user-configurable in UI; only parses a persisted string if present.
- Uses global monitor only (not local monitor/hotkey registration strategy).

### HAL driver target

**Bucket: SCAFFOLD / PLACEHOLDER**

- Driver target exists in XcodeGen/project and Objective-C++ files exist.
- Driver implementation is almost entirely stub behavior (`UnsupportedOperation`/unknown property returns).
- No real virtual device lifecycle implementation.
- XPC protocol/client exists on app side, but no integrated service host is wired.
- Driver Info.plist currently lacks required plugin factory/type metadata in repo (minimal plist), so loadability is doubtful.

### GitHub Actions release workflow

**Bucket: LIKELY BROKEN / UNVERIFIED**

- Workflow is present and structured (generate, build, export, DMG, notarize, release upload).
- High-risk issues:
  - Hardcoded `xcode-select -s /Applications/Xcode_16.app` may fail on runner naming.
  - `ExportOptions.plist` uses literal `$(APPLE_TEAM_ID)`; export options plist is not guaranteed to env-expand this string.
  - DMG background asset is a tiny placeholder PNG.
  - No proof of end-to-end successful signed+notarized release in this audit.

### Tests

**Bucket: SCAFFOLD / PLACEHOLDER**

- Tests compile at face value but are minimal and weak:
  - `DeviceManagerTests` depends on host hardware/permissions; flaky in CI.
  - `AudioAppTests` asserts a timestamp delta only; does not test engine grace-period removal logic.
  - No meaningful integration tests for tap/routing/EQ.

---

## 2) Requested Bucket Summary (per major feature)

- **WORKING IMPLEMENTATION**
  - None confidently verifiable in this environment for critical audio behavior.
- **PARTIAL IMPLEMENTATION**
  - App target shell/UI
  - Per-app volume control
  - Per-app output routing
  - EQ/effects
  - SwiftData/UserDefaults persistence
  - Launch-at-login
  - Global shortcut
- **SCAFFOLD / PLACEHOLDER**
  - HAL driver target behavior
  - Test suite quality/coverage
- **LIKELY BROKEN / UNVERIFIED**
  - AudioTap integration as production-grade per-app control
  - GitHub Actions signed/notarized DMG release realism

---

## 3) Probable Compile Errors, Entitlement Issues, API Misuse, Placeholder Logic

## High-confidence issues

- **Entitlements were previously broken**: `Nocturn/Nocturn.entitlements` was effectively empty during that audit snapshot.
  - Missing runtime permissions could block tap behavior.
- **Driver is non-functional scaffold**:
  - `NocturnDriver.mm` returns unsupported/unknown in core callbacks.
  - No real device/object model or stream IO operations.
- **Driver Info.plist likely invalid for HAL plugin loading**:
  - Current `NocturnDriver/NocturnDriver-Info.plist` is minimal and lacks plug-in factory/type keys expected by audio server plugin bundles.
- **Fake input level meter**:
  - Hardcoded constant `ProgressView(value: 0.35)` is placeholder logic.
- **Fallback app detection is wrong for “apps producing audio”**:
  - If process list is empty/fails, fallback inserts *all* running apps (`AudioEngine.detectActiveAudioPIDs`).

## Probable correctness/API risks

- **AudioTap behavioral risk**:
  - Tap path uses `.unmuted` source; processed stream may layer over original app output.
  - That may fail the core product promise (true per-app volume replacement/control).
- **Per-app routing claim mismatch**:
  - No usage of `AVAudioApplication(processIdentifier:)`.
  - Routing is via engine output device in tap session; may behave differently than claimed.
- **Concurrency strictness risk**:
  - With strict concurrency enabled, some detached task/state patterns may produce warnings/errors depending on compiler mode.

---

## 4) CATapDescription / Process Tap Validity Assessment

Short answer: **partially plausible, not proven production-valid here**.

- What is real:
  - Code uses public-looking CoreAudio symbols for process tap and aggregate devices.
- What is unverified/risky:
  - Correct entitlement state is currently not in place.
  - Correctness of tap+aggregate wiring and source mute behavior for true per-app control is not demonstrated.
  - Runtime behavior under real app audio workloads is unverified.

Conclusion: **Do not treat the current tap implementation as confirmed-working MVP quality yet.**

---

## 5) XcodeGen vs Xcode Project Coherence

**Mostly coherent, with important caveats**

- `project.yml` and generated project include app + driver + tests.
- Driver target is configured with `WRAPPER_EXTENSION = driver`, but scheme/build references still show `NocturnDriver.bundle` in places; this inconsistency is suspicious.
- `INFOPLIST_FILE` paths are wired, but file contents themselves are currently not all production-correct (notably driver plist and empty app entitlements).

---

## 6) Can the release workflow realistically produce signed/notarized DMG now?

**Classification: LIKELY BROKEN / UNVERIFIED**

Blocking/fragile points:

- Full success requires all secrets and valid cert setup (expected, but not validated here).
- Potential runner/Xcode path mismatch (`/Applications/Xcode_16.app`).
- `ExportOptions.plist` `teamID` uses literal `$(APPLE_TEAM_ID)` string, likely not resolved as intended.
- Even if archive/export runs, runtime functionality still has unresolved entitlement/audio correctness issues.

---

## 7) What blocks a first downloadable local test build?

Top blockers right now:

1. **App entitlements are empty** (critical for tap path and intended permissions).
2. **AudioTap path is unverified and likely behaviorally wrong** (possible duplicate audio due to unmuted source).
3. **Driver is scaffold only** (fine if deferred, but current repo messaging overstates readiness).
4. **Release workflow not proven and likely needs fixes** before first reliable signed/notarized artifact.
5. **Tests do not validate core behavior**; they do not protect against regressions in the promised features.

---

## Fix Next (Prioritized for real local MVP)

1. **Restore and verify app entitlements immediately**
  Put back required keys in `Nocturn/Nocturn.entitlements` and confirm codesign entitlements in built app.
2. **Make AudioTap behavior correct before polishing UI**
  Validate tap lifecycle, source mute/replace semantics, and ensure no duplicate audio. Confirm per-app volume actually isolates apps.
3. **Fix “active audio app” detection fallback**
  Do not treat all running apps as active audio apps when process-object query fails.
4. **Decide MVP boundary: disable/de-scope driver path for v0.1 test build**
  Keep HAL driver behind explicit experimental flag/status; avoid implying it works if it’s scaffold.
5. **Repair release pipeline basics**
  Fix Xcode path selection strategy, harden export options/team ID handling, and validate a full dry run with real signing assets.
6. **Upgrade tests from placeholders to behavior checks**
  Add tests for grace-period removal logic, state persistence round-trips, and unit-testable parts of routing/volume logic.
7. **Align README claims to verified reality**
  Reduce mismatch between claimed capabilities and implemented/validated behavior.