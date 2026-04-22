import AVFoundation
import Foundation
import Observation
import SwiftUI

@Observable
final class AudioTapManager {
    struct TapSession {
        let engine: AVAudioEngine
        let equalizer: AVAudioUnitEQ
        let mixer: AVAudioMixerNode
        var outputDeviceUID: String?
    }

    private(set) var sessions: [pid_t: TapSession] = [:]
    private let logger = AppLogger.audio

    /// Starts a per-app tap processing session.
    func startTap(for app: AudioApp) async throws {
        guard sessions[app.id] == nil else { return }
        let engine = AVAudioEngine()
        let equalizer = AVAudioUnitEQ(numberOfBands: 5)
        let mixer = AVAudioMixerNode()
        engine.attach(equalizer)
        engine.attach(mixer)

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        engine.connect(input, to: equalizer, format: format)
        engine.connect(equalizer, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        let session = TapSession(engine: engine, equalizer: equalizer, mixer: mixer, outputDeviceUID: app.outputDeviceUID)
        sessions[app.id] = session

        setEQBands(app.eqBands, for: app)
        setMuted(app.isMuted, for: app)
        setVolume(app.volume, for: app)

        do {
            try engine.start()
        } catch {
            sessions.removeValue(forKey: app.id)
            logger.error("Tap start failed for \(app.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AudioError.streamConfigurationFailed
        }
    }

    /// Stops and tears down a tap processing session.
    func stopTap(for app: AudioApp) {
        guard let session = sessions.removeValue(forKey: app.id) else { return }
        session.engine.stop()
    }

    /// Sets linear app volume in range 0.0...1.5.
    func setVolume(_ volume: Float, for app: AudioApp) {
        guard var session = sessions[app.id] else { return }
        let normalized = min(max(volume, 0), 1.5)
        session.mixer.outputVolume = normalized
        sessions[app.id] = session
    }

    /// Enables or disables app audio.
    func setMuted(_ muted: Bool, for app: AudioApp) {
        guard var session = sessions[app.id] else { return }
        session.mixer.outputVolume = muted ? 0 : min(max(app.volume, 0), 1.5)
        sessions[app.id] = session
    }

    /// Updates the 5-band equalizer gains in dB.
    func setEQBands(_ bands: [Float], for app: AudioApp) {
        guard var session = sessions[app.id] else { return }
        let frequencies: [Float] = [80, 250, 1_000, 4_000, 12_000]
        for index in 0..<min(5, session.equalizer.bands.count, bands.count) {
            let band = session.equalizer.bands[index]
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 1
            band.gain = min(max(bands[index], -12), 12)
            band.bypass = false
        }
        sessions[app.id] = session
    }

    /// Routes app output to a specific output device UID.
    func setOutputDevice(_ deviceUID: String, for app: AudioApp) async throws {
        guard var session = sessions[app.id] else { return }
        session.outputDeviceUID = deviceUID
        sessions[app.id] = session
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
