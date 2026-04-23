import AppKit
import CoreAudio
import Foundation
import Observation
import SwiftUI

@Observable
final class AudioEngine {
    var audioApps: [AudioApp] = []
    var tapAvailable: Bool = true
    var microphonePermissionDenied: Bool = false

    private static var didLogHostPIDAudioExclusion = false

    let deviceManager: DeviceManager
    private var tapManager: AudioTapManager?
    private let logger = AppLogger.audio

    private let pollIntervalNanoseconds: UInt64 = 2_000_000_000
    private let gracePeriod: TimeInterval = 3.0
    private var pollTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init(deviceManager: DeviceManager = DeviceManager(), tapManager: AudioTapManager? = nil) {
        self.deviceManager = deviceManager
        self.tapManager = tapManager
        // Never derive tap support from `tapManager == nil` (orphan engines / timing).
        self.tapAvailable = AudioTapManager.queryTapRuntimeCapability()
        logger.info(
            "AudioEngine initialized. tapAvailable=\(self.tapAvailable, privacy: .public) (source: shared AudioTapManager.queryTapRuntimeCapability cache; tapManager wired=\(tapManager != nil, privacy: .public))"
        )
        startPolling()
        observeTerminations()
    }

    deinit {
        pollTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func attachTapManager(_ manager: AudioTapManager) {
        tapManager = manager
        let capability = AudioTapManager.queryTapRuntimeCapability()
        if tapAvailable != capability {
            logger.warning("AudioEngine attachTapManager: reconciling tapAvailable \(self.tapAvailable) -> \(capability)")
            tapAvailable = capability
        } else {
            logger.info(
                "AudioEngine attachTapManager: manager attached; tapAvailable=\(self.tapAvailable, privacy: .public) unchanged (shared runtime capability cache)"
            )
        }
    }

    func refreshNow() async {
        await refreshActiveApps()
    }

    func tapSessionStarted(for app: AudioApp) -> Bool {
        tapManager?.hasSession(for: app.id) ?? false
    }

    func updateVolume(for app: AudioApp, volume: Float) {
        logger.info("Volume request for \(app.displayName, privacy: .public) PID \(app.id): \(volume, privacy: .public)")
        guard app.controlAvailable else {
            logger.warning("Volume request ignored for PID \(app.id): control unavailable (\(app.controlUnavailableReason ?? "unknown reason", privacy: .public))")
            return
        }
        app.volume = min(max(volume, 0), 1.0)
        tapManager?.setVolume(app.volume, for: app)
        persistState(for: app)
    }

    func updateMute(for app: AudioApp, muted: Bool) {
        logger.info("Mute request for \(app.displayName, privacy: .public) PID \(app.id): \(muted, privacy: .public)")
        guard app.controlAvailable else {
            logger.warning("Mute request ignored for PID \(app.id): control unavailable (\(app.controlUnavailableReason ?? "unknown reason", privacy: .public))")
            return
        }
        app.isMuted = muted
        tapManager?.setMuted(muted, for: app)
        persistState(for: app)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshActiveApps()
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }

    private func observeTerminations() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.removeApp(withPID: app.processIdentifier)
        }
    }

    private func refreshActiveApps() async {
        let activePIDs = detectActiveAudioPIDs()
        logger.info("Detected \(activePIDs.count) active audio process(es)")
        var existingByPID = Dictionary(uniqueKeysWithValues: audioApps.map { ($0.id, $0) })
        var updatedApps: [AudioApp] = []
        let now = Date()

        for pid in activePIDs {
            if let existing = existingByPID.removeValue(forKey: pid) {
                existing.lastActiveDate = now
                if let tm = tapManager {
                    let has = tm.hasSession(for: existing.id)
                    existing.controlAvailable = has
                    if has {
                        existing.controlFailureStep = nil
                        existing.controlUnavailableReason = nil
                    } else if tapAvailable {
                        existing.controlFailureStep = AudioTapManager.TapStartupStep.startTapSession.rawValue
                        existing.controlUnavailableReason = "Tap session not active."
                    }
                } else {
                    logger.debug(
                        "refreshActiveApps: tapManager nil; preserving control flags for PID \(existing.id, privacy: .public) (controlAvailable=\(existing.controlAvailable, privacy: .public))"
                    )
                }
                updatedApps.append(existing)
            } else if let newApp = makeAudioApp(for: pid) {
                restoreState(for: newApp)
                updatedApps.append(newApp)
                if !tapAvailable {
                    newApp.controlAvailable = false
                    newApp.controlFailureStep = AudioTapManager.TapStartupStep.startTapSession.rawValue
                    newApp.controlUnavailableReason = "AudioTap unsupported on this macOS runtime."
                    logger.warning("Control unavailable for PID \(pid): \(newApp.controlUnavailableReason ?? "", privacy: .public)")
                    continue
                }
                guard let tm = tapManager else {
                    newApp.controlAvailable = false
                    newApp.controlFailureStep = AudioTapManager.TapStartupStep.startTapSession.rawValue
                    newApp.controlUnavailableReason = "Tap manager not wired to this AudioEngine instance."
                    logger.warning(
                        "refreshActiveApps: tapManager nil; cannot start tap for PID \(pid, privacy: .public) (use the shared app AudioEngine, not the environment default)"
                    )
                    continue
                }
                do {
                    try await tm.startTap(for: newApp)
                    newApp.controlAvailable = tm.hasSession(for: newApp.id)
                    newApp.controlFailureStep = newApp.controlAvailable ? nil : AudioTapManager.TapStartupStep.startTapSession.rawValue
                    newApp.controlUnavailableReason = newApp.controlAvailable ? nil : "Tap session failed to initialize."
                    logger.info("Tap session status for PID \(pid): controlAvailable=\(newApp.controlAvailable, privacy: .public)")
                } catch {
                    newApp.controlAvailable = false
                    if let failure = error as? AudioTapManager.TapStartupFailure {
                        newApp.controlFailureStep = failure.step.rawValue
                        newApp.controlUnavailableReason = failure.detail
                    } else {
                        newApp.controlFailureStep = AudioTapManager.TapStartupStep.startTapSession.rawValue
                        newApp.controlUnavailableReason = error.localizedDescription
                    }
                    logger.error("Failed to start tap for PID \(pid): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        for stale in existingByPID.values where now.timeIntervalSince(stale.lastActiveDate) < gracePeriod {
            updatedApps.append(stale)
        }

        let removed = existingByPID.values.filter { now.timeIntervalSince($0.lastActiveDate) >= gracePeriod }
        for removedApp in removed {
            logger.info("Removing stale audio app PID \(removedApp.id)")
            tapManager?.stopTap(for: removedApp)
        }

        audioApps = updatedApps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func removeApp(withPID pid: pid_t) {
        guard let index = audioApps.firstIndex(where: { $0.id == pid }) else { return }
        let app = audioApps.remove(at: index)
        tapManager?.stopTap(for: app)
    }

    private func detectActiveAudioPIDs() -> Set<pid_t> {
        var pids = Set<pid_t>()
        var processEnumerationFailed = false
        let hostPID = ProcessInfo.processInfo.processIdentifier

        do {
            let processObjects: [AudioObjectID] = try getPropertyDataArray(
                AudioObjectID(kAudioObjectSystemObject),
                address: CoreAudioProperty.processObjectList,
                elementType: AudioObjectID.self
            )
            for processObject in processObjects {
                let pid: pid_t = (try? getPropertyData(processObject, address: CoreAudioProperty.processPID, defaultValue: pid_t(0))) ?? 0
                let running: UInt32 = (try? getPropertyData(processObject, address: CoreAudioProperty.processIsRunning, defaultValue: UInt32(0))) ?? 0
                if pid > 0, running != 0 {
                    if pid == hostPID {
                        if !Self.didLogHostPIDAudioExclusion {
                            Self.didLogHostPIDAudioExclusion = true
                            logger.info(
                                "Active audio detection: excluded Nocturn host PID \(hostPID, privacy: .public) (never treat self as an audio app to tap)"
                            )
                        } else {
                            logger.debug("Active audio detection: excluded host PID \(hostPID, privacy: .public) (repeat)")
                        }
                        continue
                    }
                    pids.insert(pid)
                }
            }
        } catch {
            processEnumerationFailed = true
            logger.error("Process audio list query failed: \(error.localizedDescription, privacy: .public)")
        }

        if processEnumerationFailed {
            // Safety behavior: never label all running processes as "playing audio".
            // Returning no entries is more honest than false positives.
            logger.warning("Active audio detection fallback: returning empty set after process enumeration failure")
            return []
        }

        logger.debug("Active audio PIDs: \(String(describing: Array(pids).sorted()), privacy: .public)")
        return pids
    }

    private func makeAudioApp(for pid: pid_t) -> AudioApp? {
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            logger.debug("makeAudioApp: skipped host PID \(pid, privacy: .public)")
            return nil
        }
        guard let running = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        if running.bundleIdentifier == Bundle.main.bundleIdentifier {
            logger.debug(
                "makeAudioApp: skipped same bundle as host \(running.bundleIdentifier ?? "", privacy: .public) PID \(pid, privacy: .public)"
            )
            return nil
        }
        let bundleID = running.bundleIdentifier ?? "pid.\(pid)"
        let name = running.localizedName ?? bundleID
        return AudioApp(
            id: pid,
            bundleID: bundleID,
            displayName: name,
            icon: running.icon
        )
    }

    private func persistState(for app: AudioApp) {
        let defaults = UserDefaults.standard
        defaults.set(app.volume, forKey: "nocturn.volume.\(app.bundleID)")
        defaults.set(app.isMuted, forKey: "nocturn.mute.\(app.bundleID)")
    }

    private func restoreState(for app: AudioApp) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "nocturn.volume.\(app.bundleID)") != nil {
            app.volume = defaults.float(forKey: "nocturn.volume.\(app.bundleID)")
        }
        app.isMuted = defaults.bool(forKey: "nocturn.mute.\(app.bundleID)")
    }
}

private struct AudioEngineKey: EnvironmentKey {
    @MainActor
    static var defaultValue: AudioEngine = AudioEngine()
}

extension EnvironmentValues {
    var audioEngine: AudioEngine {
        get { self[AudioEngineKey.self] }
        set { self[AudioEngineKey.self] = newValue }
    }
}
