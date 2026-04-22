import Foundation

struct AppAudioSession: Identifiable, Hashable {
    let id: pid_t
    let bundleID: String
    var volume: Float
    var isMuted: Bool
    var outputDeviceUID: String?
    var eqPreset: EQPreset
    var eqBands: [Float]
}
