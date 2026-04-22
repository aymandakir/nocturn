import AVFoundation
import CoreAudio
import Foundation
import Observation
import SwiftUI

/// Manages per-process audio taps on macOS 14.2+ via `CATapDescription` and an
/// aggregate device that exposes the captured audio to `AVAudioEngine`.
///
/// Each active `AudioApp` gets its own `TapSession`, which owns:
/// - a process tap (`AudioHardwareCreateProcessTap`)
/// - a private aggregate device containing that tap as a sub-tap
/// - an `AVAudioEngine` subgraph: aggregate input → EQ → mixer → output device
@Observable
final class AudioTapManager {
    struct TapSession {
        var processObjectID: AudioObjectID
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        let engine: AVAudioEngine
        let equalizer: AVAudioUnitEQ
        let mixer: AVAudioMixerNode
        var outputDeviceUID: String?
    }

    private(set) var sessions: [pid_t: TapSession] = [:]
    private let logger = AppLogger.audio

    /// True when the current macOS supports per-process AudioTap.
    var isTapAvailable: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    deinit {
        // Best-effort: unwind sessions. Individual sessions hold CoreAudio
        // resources that must be destroyed to release the aggregate device
        // and process tap, otherwise they leak across app restarts.
        for session in sessions.values {
            if session.engine.isRunning {
                session.engine.stop()
            }
            if session.aggregateID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyAggregateDevice(session.aggregateID)
            }
            if session.tapID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyProcessTap(session.tapID)
            }
        }
    }

    /// Starts a per-app tap processing session for the given app.
    func startTap(for app: AudioApp) async throws {
        guard sessions[app.id] == nil else { return }
        guard #available(macOS 14.2, *) else {
            throw AudioError.tapUnavailable
        }

        let processObjectID = try findProcessObjectID(for: app.id)
        let tapID = try createProcessTap(for: processObjectID)
        let aggregateID: AudioObjectID
        do {
            aggregateID = try createAggregateDevice(wrapping: tapID, pid: app.id)
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }

        let engine = AVAudioEngine()
        let equalizer = AVAudioUnitEQ(numberOfBands: 5)
        let mixer = AVAudioMixerNode()
        engine.attach(equalizer)
        engine.attach(mixer)

        try configureInputUnit(engine: engine, deviceID: aggregateID)

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: equalizer, format: inputFormat)
        engine.connect(equalizer, to: mixer, format: inputFormat)
        engine.connect(mixer, to: engine.mainMixerNode, format: inputFormat)

        var session = TapSession(
            processObjectID: processObjectID,
            tapID: tapID,
            aggregateID: aggregateID,
            engine: engine,
            equalizer: equalizer,
            mixer: mixer,
            outputDeviceUID: app.outputDeviceUID
        )
        sessions[app.id] = session

        EffectsChain.configure(equalizer: equalizer, bands: app.eqBands)
        setVolume(app.volume, for: app)
        setMuted(app.isMuted, for: app)
        if let uid = app.outputDeviceUID {
            try? applyOutputDevice(uid, to: &session)
            sessions[app.id] = session
        }

        do {
            try engine.start()
            logger.info("Started tap for PID \(app.id) (\(app.displayName, privacy: .public))")
        } catch {
            teardown(session)
            sessions.removeValue(forKey: app.id)
            logger.error("Engine start failed for PID \(app.id): \(error.localizedDescription, privacy: .public)")
            throw AudioError.streamConfigurationFailed
        }
    }

    /// Stops and tears down a tap processing session.
    func stopTap(for app: AudioApp) {
        guard let session = sessions.removeValue(forKey: app.id) else { return }
        teardown(session)
        logger.info("Stopped tap for PID \(app.id)")
    }

    /// Stops every active session. Safe to call from deinit paths.
    func stopAll() {
        for (pid, session) in sessions {
            teardown(session)
            logger.info("Stopped tap for PID \(pid)")
        }
        sessions.removeAll()
    }

    /// Sets linear app volume in range 0.0...1.5.
    func setVolume(_ volume: Float, for app: AudioApp) {
        guard var session = sessions[app.id] else { return }
        let normalized = min(max(volume, 0), 1.5)
        session.mixer.outputVolume = app.isMuted ? 0 : normalized
        sessions[app.id] = session
    }

    /// Enables or disables app audio without altering the stored volume.
    func setMuted(_ muted: Bool, for app: AudioApp) {
        guard var session = sessions[app.id] else { return }
        session.mixer.outputVolume = muted ? 0 : min(max(app.volume, 0), 1.5)
        sessions[app.id] = session
    }

    /// Updates the 5-band equalizer gains in dB.
    func setEQBands(_ bands: [Float], for app: AudioApp) {
        guard let session = sessions[app.id] else { return }
        EffectsChain.configure(equalizer: session.equalizer, bands: bands)
    }

    /// Routes app output to a specific output device UID.
    func setOutputDevice(_ deviceUID: String, for app: AudioApp) async throws {
        guard var session = sessions[app.id] else { return }
        try applyOutputDevice(deviceUID, to: &session)
        sessions[app.id] = session
    }

    private func teardown(_ session: TapSession) {
        if session.engine.isRunning {
            session.engine.stop()
        }
        if session.aggregateID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(session.aggregateID)
        }
        if session.tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(session.tapID)
        }
    }

    private func findProcessObjectID(for pid: pid_t) throws -> AudioObjectID {
        let processObjects: [AudioObjectID] = try getPropertyDataArray(
            AudioObjectID(kAudioObjectSystemObject),
            address: CoreAudioProperty.processObjectList,
            elementType: AudioObjectID.self
        )
        for obj in processObjects {
            let candidatePID: pid_t = (try? getPropertyData(
                obj,
                address: CoreAudioProperty.processPID,
                defaultValue: pid_t(0)
            )) ?? 0
            if candidatePID == pid {
                return obj
            }
        }
        throw AudioError.deviceNotFound
    }

    @available(macOS 14.2, *)
    private func createProcessTap(for processObjectID: AudioObjectID) throws -> AudioObjectID {
        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.uuid = UUID()
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            throw AudioError.propertyWriteFailed(status)
        }
        return tapID
    }

    @available(macOS 14.2, *)
    private func createAggregateDevice(wrapping tapID: AudioObjectID, pid: pid_t) throws -> AudioObjectID {
        let tapUID: String = (try? getCFStringProperty(
            tapID,
            selector: kAudioTapPropertyUID
        )) ?? UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Nocturn-\(pid)",
            kAudioAggregateDeviceUIDKey as String: "com.aymandakir.nocturn.tap.\(pid)",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUID,
                    kAudioSubTapDriftCompensationKey as String: false,
                ]
            ],
        ]

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != kAudioObjectUnknown else {
            throw AudioError.propertyWriteFailed(status)
        }
        return aggregateID
    }

    private func configureInputUnit(engine: AVAudioEngine, deviceID: AudioDeviceID) throws {
        guard let inputUnit = engine.inputNode.audioUnit else {
            throw AudioError.streamConfigurationFailed
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout.size(ofValue: device))
        )
        guard status == noErr else {
            throw AudioError.streamConfigurationFailed
        }
    }

    private func applyOutputDevice(_ uid: String, to session: inout TapSession) throws {
        session.outputDeviceUID = uid
        guard
            let deviceID = lookupDeviceID(forUID: uid),
            let outputUnit = session.engine.outputNode.audioUnit
        else {
            return
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout.size(ofValue: device))
        )
        guard status == noErr else {
            throw AudioError.propertyWriteFailed(status)
        }
    }

    private func lookupDeviceID(forUID uid: String) -> AudioDeviceID? {
        guard
            let ids: [AudioDeviceID] = try? getPropertyDataArray(
                AudioObjectID(kAudioObjectSystemObject),
                address: CoreAudioProperty.devices,
                elementType: AudioDeviceID.self
            )
        else { return nil }

        for id in ids {
            if let candidate = try? getCFStringProperty(id, selector: kAudioDevicePropertyDeviceUID),
               candidate == uid {
                return id
            }
        }
        return nil
    }

    private func getCFStringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw AudioError.propertyReadFailed(status)
        }
        return value as String
    }
}

private struct AudioTapManagerKey: EnvironmentKey {
    static var defaultValue: AudioTapManager = AudioTapManager()
}

extension EnvironmentValues {
    var audioTapManager: AudioTapManager {
        get { self[AudioTapManagerKey.self] }
        set { self[AudioTapManagerKey.self] = newValue }
    }
}
