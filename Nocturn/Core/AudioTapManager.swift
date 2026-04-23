@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import Observation
import AudioToolbox

// MARK: - Tap runtime capability (process-wide, stable)

extension AudioTapManager {
    /// macOS 14.2+ AudioTap availability, resolved once per process and reused everywhere.
    static func queryTapRuntimeCapability() -> Bool {
        capabilityLock.lock()
        defer { capabilityLock.unlock() }
        if let cached = cachedTapRuntimeSupported {
            return cached
        }
        let supported: Bool
        if #available(macOS 14.2, *) {
            supported = true
        } else {
            supported = false
        }
        cachedTapRuntimeSupported = supported
        if !didLogTapRuntimeCapability {
            didLogTapRuntimeCapability = true
            AppLogger.audio.info(
                "Tap runtime capability resolved: supported=\(supported, privacy: .public) (source: macOS 14.2+ availability gate, cached for process lifetime)"
            )
        }
        return supported
    }

    private static let capabilityLock = NSLock()
    private static var cachedTapRuntimeSupported: Bool?
    private static var didLogTapRuntimeCapability = false

    /// Nocturn must never tap its own process.
    static var excludedHostProcessID: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }
}

/// Manages per-process audio taps on macOS 14.2+ via `CATapDescription` and an
/// aggregate device that exposes the captured audio to `AVAudioEngine`.
///
/// Each active `AudioApp` gets its own `TapSession`, which owns:
/// - a process tap (`AudioHardwareCreateProcessTap`)
/// - a private aggregate device containing that tap as a sub-tap
/// - an `AVAudioEngine` subgraph: aggregate input → tap bridge mixer (native tap
///   format) → volume mixer (normalized hardware format) → main mixer → output
///
/// SAFETY NOTE:
/// v0.1.0 intentionally prioritizes "no duplicate audio" over perfect per-app
/// isolation. We request the source process to be muted while tapped and treat
/// this path as best-effort post-processing with per-session controls.
/// TODO(v0.2.0/HAL): move hard per-app isolation guarantees to the driver path.
@Observable
final class AudioTapManager {
    enum TapStartupStep: String {
        case detectProcess = "detect process"
        case createAggregateDevice = "create aggregate device"
        case startTapSession = "start tap session"
        case configureAudioStream = "configure audio stream"
        case applyVolumeMute = "apply volume/mute"
    }

    struct TapStartupFailure: LocalizedError {
        let step: TapStartupStep
        let detail: String

        var errorDescription: String? {
            "\(step.rawValue) failed: \(detail)"
        }
    }

    struct TapSession {
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        let engine: AVAudioEngine
        /// Receives the tap at its native format before conversion to the graph format.
        let tapBridgeMixer: AVAudioMixerNode
        /// Final pre–main-mixer stage; `outputVolume` applies per-app gain here.
        let mixer: AVAudioMixerNode
        let diagnosticsTapsInstalled: Bool
    }

    /// Bridges `AVAudioPCMBuffer` into `@Sendable` converter input blocks.
    private final class PCMBufferCapture: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private(set) var sessions: [pid_t: TapSession] = [:]
    private let logger = AppLogger.audio

    /// Coalesces concurrent `startTap` calls for the same PID (e.g. overlapping refreshes).
    private let startTapCoalesceLock = NSLock()
    private var startTapCoalesceTasks: [pid_t: Task<Void, Error>] = [:]

    /// Keep aggregate UIDs unique per startup attempt to avoid stale UID
    /// collisions that can trigger 'nope' failures from CoreAudio.
    private func makeAggregateUID(for pid: pid_t) -> String {
        "com.aymandakir.nocturn.tap.\(pid).\(UUID().uuidString.lowercased())"
    }

    /// True when the current macOS supports per-process AudioTap (cached, process-wide).
    var isTapAvailable: Bool {
        Self.queryTapRuntimeCapability()
    }

    func hasSession(for pid: pid_t) -> Bool {
        sessions[pid] != nil
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
            if #available(macOS 14.2, *), session.tapID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyProcessTap(session.tapID)
            }
        }
    }

    /// Starts a per-app tap processing session for the given app.
    func startTap(for app: AudioApp) async throws {
        guard app.id != Self.excludedHostProcessID else {
            logger.warning(
                "Tap startup rejected: excluded Nocturn host PID \(app.id, privacy: .public) (never tap self)"
            )
            return
        }

        startTapCoalesceLock.lock()
        if let inFlight = startTapCoalesceTasks[app.id] {
            startTapCoalesceLock.unlock()
            logger.info(
                "Tap startup [PID \(app.id)] coalesced: awaiting in-flight start (duplicate concurrent request)"
            )
            try await inFlight.value
            return
        }
        let task = Task { try await self.performStartTap(for: app) }
        startTapCoalesceTasks[app.id] = task
        startTapCoalesceLock.unlock()
        defer {
            startTapCoalesceLock.lock()
            startTapCoalesceTasks.removeValue(forKey: app.id)
            startTapCoalesceLock.unlock()
        }
        try await task.value
    }

    private func performStartTap(for app: AudioApp) async throws {
        guard sessions[app.id] == nil else {
            logger.info("Tap startup [PID \(app.id)] skipped: session already active for this PID")
            return
        }
        guard #available(macOS 14.2, *) else {
            logger.warning("Tap unsupported for PID \(app.id): macOS < 14.2")
            throw TapStartupFailure(step: .startTapSession, detail: AudioError.tapUnavailable.localizedDescription)
        }

        logger.info("Tap startup [PID \(app.id)] step: detect process")
        let processObjectID: AudioObjectID
        do {
            processObjectID = try findProcessObjectID(for: app.id)
        } catch {
            logger.error("Tap startup [PID \(app.id)] detect process failed: \(error.localizedDescription, privacy: .public)")
            throw TapStartupFailure(step: .detectProcess, detail: error.localizedDescription)
        }

        logger.info("Tap startup [PID \(app.id)] step: start tap session")
        let tapID: AudioObjectID
        do {
            tapID = try createProcessTap(for: processObjectID)
        } catch {
            logger.error("Tap startup [PID \(app.id)] start tap session failed: \(error.localizedDescription, privacy: .public)")
            throw TapStartupFailure(step: .startTapSession, detail: error.localizedDescription)
        }

        logger.info("Tap startup [PID \(app.id)] step: create aggregate device")
        let aggregateID: AudioObjectID
        do {
            aggregateID = try createAggregateDevice(wrapping: tapID, pid: app.id)
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            logger.error("Tap startup [PID \(app.id)] create aggregate device failed: \(error.localizedDescription, privacy: .public)")
            throw TapStartupFailure(step: .createAggregateDevice, detail: error.localizedDescription)
        }

        let engine = AVAudioEngine()
        let tapBridgeMixer = AVAudioMixerNode()
        let volumeMixer = AVAudioMixerNode()
        engine.attach(tapBridgeMixer)
        engine.attach(volumeMixer)

        logger.info("Tap startup [PID \(app.id)] step: configure audio stream")
        do {
            try configureAudioUnits(engine: engine, inputDeviceID: aggregateID)
            let tapInputFormat = engine.inputNode.inputFormat(forBus: 0)
            let tapOutputFormat = engine.inputNode.outputFormat(forBus: 0)
            let outputNodeInputFormat = engine.outputNode.inputFormat(forBus: 0)
            let outputNodeOutputFormat = engine.outputNode.outputFormat(forBus: 0)
            logger.info(
                """
                Tap startup [PID \(app.id)] formats (pre-graph):
                tapInput sr=\(tapInputFormat.sampleRate, privacy: .public) ch=\(tapInputFormat.channelCount, privacy: .public)
                tapOutput sr=\(tapOutputFormat.sampleRate, privacy: .public) ch=\(tapOutputFormat.channelCount, privacy: .public)
                hwOutput(input bus) sr=\(outputNodeInputFormat.sampleRate, privacy: .public) ch=\(outputNodeInputFormat.channelCount, privacy: .public)
                hwOutput(output bus) sr=\(outputNodeOutputFormat.sampleRate, privacy: .public) ch=\(outputNodeOutputFormat.channelCount, privacy: .public)
                """
            )

            guard tapOutputFormat.channelCount > 0, tapOutputFormat.sampleRate > 0 else {
                throw TapStartupFailure(
                    step: .configureAudioStream,
                    detail: "Invalid tap stream format (sampleRate/channels not usable)."
                )
            }
            guard outputNodeInputFormat.channelCount > 0, outputNodeInputFormat.sampleRate > 0 else {
                throw TapStartupFailure(
                    step: .configureAudioStream,
                    detail: "Invalid output hardware format before start (input bus sr=\(outputNodeInputFormat.sampleRate), ch=\(outputNodeInputFormat.channelCount))."
                )
            }
            guard outputNodeOutputFormat.channelCount > 0, outputNodeOutputFormat.sampleRate > 0 else {
                throw TapStartupFailure(
                    step: .configureAudioStream,
                    detail: "Invalid output hardware format before start (output bus sr=\(outputNodeOutputFormat.sampleRate), ch=\(outputNodeOutputFormat.channelCount))."
                )
            }

            let graphFormat = try makeNormalizedGraphFormat(matchingHardware: outputNodeInputFormat)
            try validateTapToGraphConversion(from: tapOutputFormat, to: graphFormat, pid: app.id)

            logger.info(
                """
                Tap startup [PID \(app.id)] normalized graph format:
                \(self.describeAudioFormat(graphFormat), privacy: .public)
                tapNative=\(self.describeAudioFormat(tapOutputFormat), privacy: .public)
                """
            )

            engine.connect(engine.inputNode, to: tapBridgeMixer, format: tapOutputFormat)
            logger.info(
                "Tap startup [PID \(app.id)] connect negotiated: inputNode->tapBridgeMixer format=\(self.describeAudioFormat(tapOutputFormat), privacy: .public)"
            )

            engine.connect(tapBridgeMixer, to: volumeMixer, format: graphFormat)
            logger.info(
                "Tap startup [PID \(app.id)] connect negotiated: tapBridgeMixer->volumeMixer format=\(self.describeAudioFormat(graphFormat), privacy: .public)"
            )

            engine.connect(volumeMixer, to: engine.mainMixerNode, format: graphFormat)
            logger.info(
                "Tap startup [PID \(app.id)] connect negotiated: volumeMixer->mainMixer format=\(self.describeAudioFormat(graphFormat), privacy: .public)"
            )

            engine.prepare()

            let bridgeIn = tapBridgeMixer.inputFormat(forBus: 0)
            let bridgeOut = tapBridgeMixer.outputFormat(forBus: 0)
            let volIn = volumeMixer.inputFormat(forBus: 0)
            let volOut = volumeMixer.outputFormat(forBus: 0)
            let mainIn = engine.mainMixerNode.inputFormat(forBus: 0)
            let mainOut = engine.mainMixerNode.outputFormat(forBus: 0)
            let outIn = engine.outputNode.inputFormat(forBus: 0)
            let outOut = engine.outputNode.outputFormat(forBus: 0)
            logger.info(
                """
                Tap startup [PID \(app.id)] formats (post-prepare):
                tapBridge in/out sr=\(bridgeIn.sampleRate, privacy: .public)/\(bridgeOut.sampleRate, privacy: .public) ch=\(bridgeIn.channelCount, privacy: .public)/\(bridgeOut.channelCount, privacy: .public)
                volumeMixer in/out sr=\(volIn.sampleRate, privacy: .public)/\(volOut.sampleRate, privacy: .public) ch=\(volIn.channelCount, privacy: .public)/\(volOut.channelCount, privacy: .public)
                mainMixer in/out sr=\(mainIn.sampleRate, privacy: .public)/\(mainOut.sampleRate, privacy: .public) ch=\(mainIn.channelCount, privacy: .public)/\(mainOut.channelCount, privacy: .public)
                outputNode in/out sr=\(outIn.sampleRate, privacy: .public)/\(outOut.sampleRate, privacy: .public) ch=\(outIn.channelCount, privacy: .public)/\(outOut.channelCount, privacy: .public)
                """
            )

            guard bridgeIn.sampleRate > 0, bridgeIn.channelCount > 0,
                  bridgeOut.sampleRate > 0, bridgeOut.channelCount > 0 else {
                throw TapStartupFailure(
                    step: .configureAudioStream,
                    detail: "Invalid tap bridge mixer format after prepare: in=\(self.describeAudioFormat(bridgeIn)) out=\(self.describeAudioFormat(bridgeOut))"
                )
            }
            guard volIn.sampleRate > 0, volIn.channelCount > 0,
                  volOut.sampleRate > 0, volOut.channelCount > 0 else {
                throw TapStartupFailure(
                    step: .configureAudioStream,
                    detail: "Invalid volume mixer format after prepare: in=\(self.describeAudioFormat(volIn)) out=\(self.describeAudioFormat(volOut))"
                )
            }
            guard mainIn.sampleRate > 0, mainIn.channelCount > 0,
                  outIn.sampleRate > 0, outIn.channelCount > 0 else {
                throw TapStartupFailure(
                    step: .configureAudioStream,
                    detail: "Invalid main/output format after prepare: mainIn=\(self.describeAudioFormat(mainIn)) outputIn=\(self.describeAudioFormat(outIn))"
                )
            }
        } catch {
            logger.error("Tap startup [PID \(app.id)] configure audio stream failed: \(error.localizedDescription, privacy: .public)")
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw TapStartupFailure(step: .configureAudioStream, detail: error.localizedDescription)
        }

        let session = TapSession(
            tapID: tapID,
            aggregateID: aggregateID,
            engine: engine,
            tapBridgeMixer: tapBridgeMixer,
            mixer: volumeMixer,
            diagnosticsTapsInstalled: shouldInstallFlowDiagnosticsTaps()
        )
        sessions[app.id] = session

        if session.diagnosticsTapsInstalled {
            installFlowDiagnosticsTaps(
                pid: app.id,
                tapBridgeMixer: tapBridgeMixer,
                volumeMixer: volumeMixer,
                mainMixer: engine.mainMixerNode
            )
        } else {
            logger.info("Tap startup [PID \(app.id)] flow diagnostics taps disabled (set UserDefaults nocturn.diagnosticsMode=true to enable)")
        }

        logger.info("Tap startup [PID \(app.id)] step: apply volume/mute")
        setVolume(app.volume, for: app)
        setMuted(app.isMuted, for: app)

        do {
            let currentDefaultOutputID = currentDefaultOutputDeviceID() ?? 0
            let currentDefaultOutputUID = currentDefaultDeviceUID(isInput: false) ?? "unresolved"
            let startOutputInputFormat = engine.outputNode.inputFormat(forBus: 0)
            let startOutputOutputFormat = engine.outputNode.outputFormat(forBus: 0)
            logger.info(
                """
                Tap startup [PID \(app.id)] pre-start output formats:
                defaultOutputDeviceID=\(currentDefaultOutputID, privacy: .public)
                defaultOutputDeviceUID=\(currentDefaultOutputUID, privacy: .public)
                outputNode.input sr=\(startOutputInputFormat.sampleRate, privacy: .public) ch=\(startOutputInputFormat.channelCount, privacy: .public)
                outputNode.output sr=\(startOutputOutputFormat.sampleRate, privacy: .public) ch=\(startOutputOutputFormat.channelCount, privacy: .public)
                """
            )
            try engine.start()
            let runningInputDeviceID = readCurrentDevice(inputUnit: engine.inputNode.audioUnit)
            let runningOutputDeviceID = readCurrentDevice(inputUnit: engine.outputNode.audioUnit)
            let inputDeviceMatchesAggregate = runningInputDeviceID == aggregateID
            let outputDeviceMatchesAggregate = runningOutputDeviceID == aggregateID
            logger.info(
                "Tap startup [PID \(app.id)] inputNode running deviceID=\(runningInputDeviceID, privacy: .public) (expected=\(aggregateID, privacy: .public), match=\(inputDeviceMatchesAggregate, privacy: .public))"
            )
            logger.info(
                "Tap startup [PID \(app.id)] outputNode running deviceID=\(runningOutputDeviceID, privacy: .public) (expected=\(aggregateID, privacy: .public), match=\(outputDeviceMatchesAggregate, privacy: .public))"
            )
            if !inputDeviceMatchesAggregate {
                logger.error(
                    "input device mismatch: engine routed to \(runningInputDeviceID, privacy: .public), expected aggregate \(aggregateID, privacy: .public)"
                )
            }
            if !outputDeviceMatchesAggregate {
                logger.error(
                    "output device mismatch: engine routed to \(runningOutputDeviceID, privacy: .public), expected aggregate \(aggregateID, privacy: .public)"
                )
            }
            if inputDeviceMatchesAggregate && outputDeviceMatchesAggregate {
                let beforeProbe = volumeMixer.outputVolume
                volumeMixer.outputVolume = beforeProbe
                logger.info(
                    "Tap startup [PID \(app.id)] volume mixer control probe write succeeded: outputVolume=\(beforeProbe, privacy: .public)"
                )
            }
            let postStartOutputID = currentDefaultOutputDeviceID() ?? 0
            let postStartOutputUID = currentDefaultDeviceUID(isInput: false) ?? "unresolved"
            logger.info(
                """
                Tap startup [PID \(app.id)] playback route:
                postStartDefaultOutputDeviceID=\(postStartOutputID, privacy: .public)
                postStartDefaultOutputDeviceUID=\(postStartOutputUID, privacy: .public)
                """
            )
            logger.info("Tap startup [PID \(app.id)] success: started for \(app.displayName, privacy: .public)")
        } catch {
            teardown(session)
            sessions.removeValue(forKey: app.id)
            logger.error("Tap startup [PID \(app.id)] start tap session failed: \(error.localizedDescription, privacy: .public)")
            throw TapStartupFailure(
                step: .configureAudioStream,
                detail: "AVAudioEngine start failed after graph normalization (tap→bridge→volume→main): \(error.localizedDescription)"
            )
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
        guard let session = sessions[app.id] else {
            logger.warning("Volume apply skipped for PID \(app.id): no tap session")
            return
        }
        let normalized = min(max(volume, 0), 1.5)
        session.mixer.outputVolume = app.isMuted ? 0 : normalized
        logger.debug("Applied volume \(normalized, privacy: .public) for PID \(app.id)")
    }

    /// Enables or disables app audio without altering the stored volume.
    func setMuted(_ muted: Bool, for app: AudioApp) {
        guard let session = sessions[app.id] else {
            logger.warning("Mute apply skipped for PID \(app.id): no tap session")
            return
        }
        session.mixer.outputVolume = muted ? 0 : min(max(app.volume, 0), 1.5)
        logger.debug("Applied mute \(muted, privacy: .public) for PID \(app.id)")
    }

    private func teardown(_ session: TapSession) {
        if session.diagnosticsTapsInstalled {
            session.tapBridgeMixer.removeTap(onBus: 0)
            session.mixer.removeTap(onBus: 0)
            session.engine.mainMixerNode.removeTap(onBus: 0)
        }
        if session.engine.isRunning {
            session.engine.stop()
        }
        if session.aggregateID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(session.aggregateID)
        }
        if #available(macOS 14.2, *), session.tapID != kAudioObjectUnknown {
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
        // Avoid layering original + processed signal. This mutes the source app
        // while Nocturn is rendering the tapped stream.
        description.muteBehavior = .muted
        let sourceMutedByTap = description.muteBehavior == .muted
        let passthroughEnabled = description.muteBehavior == .unmuted
        logger.info(
            """
            Tap description:
            muteBehavior=\(self.describeMuteBehavior(description.muteBehavior), privacy: .public)
            sourceMutedByTap=\(sourceMutedByTap, privacy: .public)
            tapPassthroughEnabled=\(passthroughEnabled, privacy: .public)
            """
        )

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
        let aggregateUID = makeAggregateUID(for: pid)
        let aggregateName = "Nocturn-\(pid)"
        let defaultOutputUID = currentDefaultDeviceUID(isInput: false) ?? "unresolved"
        let defaultInputUID = currentDefaultDeviceUID(isInput: true) ?? "unresolved"
        guard defaultOutputUID != "unresolved" else {
            throw TapStartupFailure(
                step: .createAggregateDevice,
                detail: "Cannot build combined aggregate: default output UID unresolved."
            )
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: aggregateName,
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: NSNumber(value: true),
            kAudioAggregateDeviceIsStackedKey as String: NSNumber(value: false),
            kAudioAggregateDeviceTapAutoStartKey as String: NSNumber(value: true),
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUID,
                    kAudioSubTapDriftCompensationKey as String: NSNumber(value: false),
                ]
            ],
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [
                    kAudioSubDeviceUIDKey as String: defaultOutputUID
                ]
            ],
        ]
        logger.info(
            """
            Tap startup [PID \(pid)] aggregate description:
            full=\(String(describing: description), privacy: .public)
            name=\(aggregateName, privacy: .public)
            uid=\(aggregateUID, privacy: .public)
            tapUID=\(tapUID, privacy: .public)
            outputSubDeviceUID=\(defaultOutputUID, privacy: .public)
            aggregateIsPrivate=true
            aggregateIsStacked=false
            aggregateTapAutoStart=true
            defaultOutputUID=\(defaultOutputUID, privacy: .public)
            defaultInputUID=\(defaultInputUID, privacy: .public)
            """
        )
        logger.info(
            """
            Tap startup [PID \(pid)] UID resolution pre-create:
            tapUIDExistsAsDevice=\(self.lookupDeviceID(forUID: tapUID) != nil, privacy: .public)
            defaultOutputUIDExists=\(self.lookupDeviceID(forUID: defaultOutputUID) != nil, privacy: .public)
            defaultInputUIDExists=\(self.lookupDeviceID(forUID: defaultInputUID) != nil, privacy: .public)
            aggregateUIDExists(pre)=\(self.lookupDeviceID(forUID: aggregateUID) != nil, privacy: .public)
            """
        )

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != kAudioObjectUnknown else {
            throw TapStartupFailure(
                step: .createAggregateDevice,
                detail: "AudioHardwareCreateAggregateDevice status=\(status) (\(decodeOSStatus(status)))"
            )
        }
        let fetchedAfterCreate = lookupDeviceID(forUID: aggregateUID)
        logger.info(
            """
            Tap startup [PID \(pid)] aggregate create result:
            returnedAggregateID=\(aggregateID, privacy: .public)
            fetchedByUIDAfterCreate=\(String(describing: fetchedAfterCreate), privacy: .public)
            """
        )
        return aggregateID
    }

    private func configureAudioUnits(engine: AVAudioEngine, inputDeviceID: AudioDeviceID) throws {
        guard let inputUnit = engine.inputNode.audioUnit else {
            throw AudioError.streamConfigurationFailed
        }
        guard let outputUnit = engine.outputNode.audioUnit else {
            throw TapStartupFailure(step: .configureAudioStream, detail: "Output audio unit unavailable.")
        }

        let aggregateDeviceID = inputDeviceID
        let outputAU = engine.outputNode.auAudioUnit
        logAudioUnitIdentity(
            label: "inputNode",
            node: engine.inputNode,
            targetDeviceID: aggregateDeviceID
        )
        logAudioUnitIdentity(
            label: "outputNode",
            node: engine.outputNode,
            targetDeviceID: aggregateDeviceID
        )

        do {
            try outputAU.setDeviceID(aggregateDeviceID)
            logger.info(
                "Tap startup configureAudioUnits output AUAudioUnit.setDeviceID success: combinedAggregateDeviceID=\(aggregateDeviceID, privacy: .public)"
            )
        } catch {
            throw TapStartupFailure(
                step: .configureAudioStream,
                detail: "AUAudioUnit output setDeviceID failed for combined aggregate \(aggregateDeviceID): \(error.localizedDescription)"
            )
        }
        logger.info(
            """
            Tap startup configureAudioUnits single-device routing:
            combinedAggregateDeviceID=\(aggregateDeviceID, privacy: .public)
            inputCurrentDeviceWrite=removed (single shared AVAudioEngine I/O device model)
            outputCurrentDeviceWrite=removed (single shared AVAudioEngine I/O device model)
            outputAUAudioUnitSetDeviceID=applied to combined aggregate
            """
        )

        var readBackInputDevice = AudioDeviceID(0)
        var readBackSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let readBackInputStatus = AudioUnitGetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &readBackInputDevice,
            &readBackSize
        )
        let inputReadBackText: String
        if readBackInputStatus == noErr {
            inputReadBackText = "supported"
        } else {
            inputReadBackText = "unsupported status=\(readBackInputStatus) (\(decodeOSStatus(readBackInputStatus)))"
        }
        var readBackOutputDevice = AudioDeviceID(0)
        var outputReadBackSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let readBackOutputStatus = AudioUnitGetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &readBackOutputDevice,
            &outputReadBackSize
        )
        let outputReadBackText: String
        if readBackOutputStatus == noErr {
            outputReadBackText = "supported"
        } else {
            outputReadBackText = "unsupported status=\(readBackOutputStatus) (\(decodeOSStatus(readBackOutputStatus)))"
        }
        let inputReadBackUID = deviceUID(for: readBackInputDevice) ?? "unresolved"
        let outputReadBackUID = deviceUID(for: readBackOutputDevice) ?? "unresolved"
        logger.info(
            """
            Tap startup configureAudioUnits:
            inputTargetDeviceID=\(aggregateDeviceID, privacy: .public)
            outputTargetDeviceID=\(aggregateDeviceID, privacy: .public)
            inputReadBackStatus=\(readBackInputStatus, privacy: .public) (\(self.decodeOSStatus(readBackInputStatus), privacy: .public))
            inputReadBackDeviceID=\(readBackInputDevice, privacy: .public)
            inputReadBackDeviceUID=\(inputReadBackUID, privacy: .public)
            inputCurrentDeviceReadSupport=\(inputReadBackText, privacy: .public)
            outputReadBackStatus=\(readBackOutputStatus, privacy: .public) (\(self.decodeOSStatus(readBackOutputStatus), privacy: .public))
            outputReadBackDeviceID=\(readBackOutputDevice, privacy: .public)
            outputReadBackDeviceUID=\(outputReadBackUID, privacy: .public)
            outputCurrentDeviceReadSupport=\(outputReadBackText, privacy: .public)
            """
        )
    }

    private func lookupDeviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
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

    private func currentDefaultDeviceUID(isInput: Bool) -> String? {
        let selector = isInput
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        guard status == noErr else { return nil }
        return try? getCFStringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        guard status == noErr, id != 0 else { return nil }
        return id
    }

    private func deviceUID(for id: AudioDeviceID) -> String? {
        guard id != 0 else { return nil }
        return try? getCFStringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private func readCurrentDevice(inputUnit: AudioUnit?) -> AudioDeviceID {
        guard let inputUnit else { return 0 }
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &size
        )
        guard status == noErr else { return 0 }
        return deviceID
    }

    /// Single graph format aligned to hardware output (sample rate + at least stereo).
    private func makeNormalizedGraphFormat(matchingHardware hw: AVAudioFormat) throws -> AVAudioFormat {
        guard hw.sampleRate > 0, hw.channelCount > 0 else {
            throw TapStartupFailure(
                step: .configureAudioStream,
                detail: "Cannot build graph format: invalid hardware format \(describeAudioFormat(hw))."
            )
        }
        let channels = max(2, Int(hw.channelCount))
        guard let graph = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hw.sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            throw TapStartupFailure(
                step: .configureAudioStream,
                detail: "Could not build AVAudioFormat for graph (sr=\(hw.sampleRate), ch=\(channels))."
            )
        }
        return graph
    }

    /// Verifies CoreAudio can convert from the tap stream to the normalized graph path, or skips when identical.
    private func validateTapToGraphConversion(from tap: AVAudioFormat, to graph: AVAudioFormat, pid: pid_t) throws {
        if tap.sampleRate == graph.sampleRate, tap.channelCount == graph.channelCount {
            logger.info("Tap startup [PID \(pid)] tap->graph: formats already match; no conversion stage required.")
            return
        }
        guard let converter = AVAudioConverter(from: tap, to: graph) else {
            throw TapStartupFailure(
                step: .configureAudioStream,
                detail: "AVAudioConverter init returned nil for tap=\(describeAudioFormat(tap)) graph=\(describeAudioFormat(graph))."
            )
        }
        let inFrames: AVAudioFrameCount = 256
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: tap, frameCapacity: inFrames) else {
            throw TapStartupFailure(step: .configureAudioStream, detail: "Conversion probe: could not allocate tap-format buffer.")
        }
        inBuf.frameLength = inFrames
        let ratio = graph.sampleRate / max(tap.sampleRate, 1)
        let outCapacity = AVAudioFrameCount(ceil(Double(inFrames) * ratio) + 64)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: graph, frameCapacity: outCapacity) else {
            throw TapStartupFailure(step: .configureAudioStream, detail: "Conversion probe: could not allocate graph-format buffer.")
        }
        var error: NSError?
        let inputCapture = PCMBufferCapture(buffer: inBuf)
        let convertStatus = converter.convert(to: outBuf, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputCapture.buffer
        }
        guard convertStatus != .error else {
            let errText = error?.localizedDescription ?? "unknown"
            throw TapStartupFailure(
                step: .configureAudioStream,
                detail: "Tap->graph conversion probe failed (status=\(convertStatus.rawValue)): \(errText); tap=\(describeAudioFormat(tap)) graph=\(describeAudioFormat(graph))"
            )
        }
        logger.info(
            "Tap startup [PID \(pid)] tap->graph conversion probe ok: convertStatus=\(convertStatus.rawValue, privacy: .public) outputFrames=\(outBuf.frameLength, privacy: .public)"
        )
    }

    private func shouldInstallFlowDiagnosticsTaps() -> Bool {
        UserDefaults.standard.bool(forKey: "nocturn.diagnosticsMode")
    }

    private func installFlowDiagnosticsTaps(
        pid: pid_t,
        tapBridgeMixer: AVAudioMixerNode,
        volumeMixer: AVAudioMixerNode,
        mainMixer: AVAudioMixerNode
    ) {
        installFlowTap(node: tapBridgeMixer, bus: 0, label: "tapBridgeMixer", pid: pid)
        installFlowTap(node: volumeMixer, bus: 0, label: "volumeMixer", pid: pid)
        installFlowTap(node: mainMixer, bus: 0, label: "mainMixer", pid: pid)
        logger.info("Tap startup [PID \(pid)] flow diagnostics taps installed: tapBridgeMixer, volumeMixer, mainMixer")
    }

    private func installFlowTap(node: AVAudioNode, bus: AVAudioNodeBus, label: String, pid: pid_t) {
        let format = node.outputFormat(forBus: bus)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            logger.warning("Tap startup [PID \(pid)] \(label) flow tap skipped: invalid output format \(self.describeAudioFormat(format), privacy: .public)")
            return
        }

        var callbackCount = 0
        let everyNBuffers = 50
        node.installTap(onBus: bus, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            callbackCount += 1
            guard callbackCount <= 5 || callbackCount % everyNBuffers == 0 else { return }
            let rms = self?.computeRMS(buffer: buffer) ?? -1
            self?.logger.info(
                """
                Tap flow [PID \(pid)] \(label):
                callbacks=\(callbackCount, privacy: .public)
                frames=\(buffer.frameLength, privacy: .public)
                channels=\(buffer.format.channelCount, privacy: .public)
                rms=\(rms, privacy: .public)
                """
            )
        }
    }

    private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0,
            buffer.format.channelCount > 0
        else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var energy: Float = 0
        for c in 0..<channelCount {
            let samples = channelData[c]
            for i in 0..<frameCount {
                let s = samples[i]
                energy += s * s
            }
        }
        let denom = Float(channelCount * frameCount)
        guard denom > 0 else { return 0 }
        return sqrt(energy / denom)
    }

    @available(macOS 14.2, *)
    private func describeMuteBehavior(_ behavior: CATapMuteBehavior) -> String {
        switch behavior {
        case .unmuted:
            return "unmuted (passthrough to source hardware remains enabled)"
        case .muted:
            return "muted (source hardware path intercepted; audible only if tap is replayed)"
        case .mutedWhenTapped:
            return "mutedWhenTapped (source mutes while another client reads tap)"
        @unknown default:
            return "unknown(\(behavior.rawValue))"
        }
    }

    private func describeAudioFormat(_ format: AVAudioFormat) -> String {
        "sr=\(format.sampleRate) ch=\(format.channelCount) common=\(format.commonFormat.rawValue) interleaved=\(format.isInterleaved)"
    }

    private func decodeOSStatus(_ status: OSStatus) -> String {
        let n = UInt32(bitPattern: status)
        let chars: [UInt8] = [
            UInt8((n >> 24) & 0xFF),
            UInt8((n >> 16) & 0xFF),
            UInt8((n >> 8) & 0xFF),
            UInt8(n & 0xFF),
        ]
        let printable = chars.allSatisfy { $0 >= 32 && $0 <= 126 }
        if printable {
            let s = String(bytes: chars, encoding: .macOSRoman) ?? "????"
            return "'\(s)'"
        }
        return "0x\(String(n, radix: 16))"
    }

    private func logAudioUnitIdentity(
        label: String,
        node: AVAudioNode,
        targetDeviceID: AudioDeviceID
    ) {
        let description = node.auAudioUnit.componentDescription
        logger.info(
            """
            Tap startup audio unit:
            label=\(label, privacy: .public)
            targetDeviceID=\(targetDeviceID, privacy: .public)
            componentType=\(self.fourCC(description.componentType), privacy: .public)
            componentSubType=\(self.fourCC(description.componentSubType), privacy: .public)
            componentManufacturer=\(self.fourCC(description.componentManufacturer), privacy: .public)
            """
        )
    }

    private func fourCC(_ value: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
        }
        return "0x\(String(value, radix: 16))"
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
