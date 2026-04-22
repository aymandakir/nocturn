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
        let maxValue: Float = app.isBoostEnabled ? 1.5 : 1.0
        app.volume = min(max(volume, 0), maxValue)
        tapManager?.setVolume(app.volume, for: app)
        persistState(for: app)
    }

    func updateMute(for app: AudioApp, muted: Bool) {
        app.isMuted = muted
        tapManager?.setMuted(muted, for: app)
        persistState(for: app)
    }

    func updateEQPreset(for app: AudioApp, preset: EQPreset) {
        app.eqPreset = preset
        if preset != .custom {
            app.eqBands = preset.bands
        }
        tapManager?.setEQBands(app.eqBands, for: app)
        persistState(for: app)
    }

    func updateEQBands(for app: AudioApp, bands: [Float]) {
        app.eqBands = bands
        app.eqPreset = .custom
        tapManager?.setEQBands(bands, for: app)
        persistState(for: app)
    }

    func updateOutputDevice(for app: AudioApp, deviceUID: String) {
        app.outputDeviceUID = deviceUID
        Task {
            try? await tapManager?.setOutputDevice(deviceUID, for: app)
        }
        persistState(for: app)
    }

    func setBoostEnabled(for app: AudioApp, enabled: Bool) {
        app.isBoostEnabled = enabled
        if !enabled, app.volume > 1.0 {
            app.volume = 1.0
        }
        tapManager?.setVolume(app.volume, for: app)
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
        var existingByPID = Dictionary(uniqueKeysWithValues: audioApps.map { ($0.id, $0) })
        var updatedApps: [AudioApp] = []
        let now = Date()

        for pid in activePIDs {
            if let existing = existingByPID.removeValue(forKey: pid) {
                existing.lastActiveDate = now
                updatedApps.append(existing)
            } else if let newApp = makeAudioApp(for: pid) {
                restoreState(for: newApp)
                updatedApps.append(newApp)
                do {
                    try await tapManager?.startTap(for: newApp)
                } catch {
                    logger.error("Failed to start tap for PID \(pid): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        for stale in existingByPID.values where now.timeIntervalSince(stale.lastActiveDate) < gracePeriod {
            updatedApps.append(stale)
        }

        let removed = existingByPID.values.filter { now.timeIntervalSince($0.lastActiveDate) >= gracePeriod }
        for removedApp in removed {
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
            logger.error("Process audio list query failed: \(error.localizedDescription, privacy: .public)")
        }

        if pids.isEmpty {
            for app in NSWorkspace.shared.runningApplications where app.processIdentifier > 0 {
                pids.insert(app.processIdentifier)
            }
        }

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
        defaults.set(app.outputDeviceUID, forKey: "nocturn.outputDevice.\(app.bundleID)")

        let payload = EQStatePayload(preset: app.eqPreset, bands: app.eqBands)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: "nocturn.eq.\(app.bundleID)")
        }

        // Also persist richer EQ/device state through SwiftData.
        let bundleID = app.bundleID
        let preset = app.eqPreset
        let bands = app.eqBands
        let outputDeviceUID = app.outputDeviceUID
        Task { @MainActor in
            NocturnDataStore.upsert(
                bundleID: bundleID,
                preset: preset,
                bands: bands,
                outputDeviceUID: outputDeviceUID
            )
        }
    }

    private func restoreState(for app: AudioApp) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "nocturn.volume.\(app.bundleID)") != nil {
            app.volume = defaults.float(forKey: "nocturn.volume.\(app.bundleID)")
        }
        app.isMuted = defaults.bool(forKey: "nocturn.mute.\(app.bundleID)")
        app.outputDeviceUID = defaults.string(forKey: "nocturn.outputDevice.\(app.bundleID)")
        if let data = defaults.data(forKey: "nocturn.eq.\(app.bundleID)"),
           let payload = try? JSONDecoder().decode(EQStatePayload.self, from: data) {
            app.eqPreset = payload.preset
            app.eqBands = payload.bands
        }
    }
}

private struct EQStatePayload: Codable {
    let preset: EQPreset
    let bands: [Float]
}

private struct AudioEngineKey: EnvironmentKey {
    static var defaultValue: AudioEngine = AudioEngine()
}

extension EnvironmentValues {
    var audioEngine: AudioEngine {
        get { self[AudioEngineKey.self] }
        set { self[AudioEngineKey.self] = newValue }
    }
}
