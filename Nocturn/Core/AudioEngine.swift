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
        self.tapAvailable = tapManager?.isTapAvailable ?? false
        logger.info("AudioEngine initialized. Tap runtime available: \(self.tapAvailable, privacy: .public)")
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
        tapAvailable = manager.isTapAvailable
    }

    func refreshNow() async {
        await refreshActiveApps()
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
                existing.controlAvailable = tapManager?.hasSession(for: existing.id) ?? false
                if !existing.controlAvailable, tapAvailable {
                    existing.controlUnavailableReason = "Tap session not active."
                }
                updatedApps.append(existing)
            } else if let newApp = makeAudioApp(for: pid) {
                restoreState(for: newApp)
                updatedApps.append(newApp)
                if !tapAvailable {
                    newApp.controlAvailable = false
                    newApp.controlUnavailableReason = "AudioTap unsupported on this macOS runtime."
                    logger.warning("Control unavailable for PID \(pid): \(newApp.controlUnavailableReason ?? "", privacy: .public)")
                    continue
                }
                do {
                    try await tapManager?.startTap(for: newApp)
                    newApp.controlAvailable = tapManager?.hasSession(for: newApp.id) ?? false
                    newApp.controlUnavailableReason = newApp.controlAvailable ? nil : "Tap session failed to initialize."
                    logger.info("Tap session status for PID \(pid): controlAvailable=\(newApp.controlAvailable, privacy: .public)")
                } catch {
                    newApp.controlAvailable = false
                    newApp.controlUnavailableReason = "Tap start failed: \(error.localizedDescription)"
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
        guard let running = NSRunningApplication(processIdentifier: pid) else {
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
