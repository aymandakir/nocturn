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
    var lastActiveDate: Date

    init(
        id: pid_t,
        bundleID: String,
        displayName: String,
        icon: NSImage?,
        volume: Float = 1.0,
        isMuted: Bool = false,
        lastActiveDate: Date = .now
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.icon = icon
        self.volume = volume
        self.isMuted = isMuted
        self.lastActiveDate = lastActiveDate
    }
}
