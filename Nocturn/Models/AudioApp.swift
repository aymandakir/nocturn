import AppKit
import Foundation
import Observation

@Observable
final class AudioApp: Identifiable {
    let id: pid_t
    let bundleID: String
    let displayName: String
    let icon: NSImage?
    var volume: Float
    var isMuted: Bool
    var outputDeviceUID: String?
    var eqPreset: EQPreset
    var eqBands: [Float]
    var lastActiveDate: Date
    var isBoostEnabled: Bool

    init(
        id: pid_t,
        bundleID: String,
        displayName: String,
        icon: NSImage?,
        volume: Float = 1.0,
        isMuted: Bool = false,
        outputDeviceUID: String? = nil,
        eqPreset: EQPreset = .flat,
        eqBands: [Float] = [0, 0, 0, 0, 0],
        lastActiveDate: Date = .now,
        isBoostEnabled: Bool = false
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.icon = icon
        self.volume = volume
        self.isMuted = isMuted
        self.outputDeviceUID = outputDeviceUID
        self.eqPreset = eqPreset
        self.eqBands = eqBands
        self.lastActiveDate = lastActiveDate
        self.isBoostEnabled = isBoostEnabled
    }
}
