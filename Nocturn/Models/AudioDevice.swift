import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    enum DeviceType: String, Codable, Hashable {
        case builtIn
        case headphones
        case airPlay
        case bluetooth
        case virtual
        case speaker
        case unknown
    }

    let id: AudioDeviceID
    let name: String
    let uid: String
    let isInput: Bool
    let isOutput: Bool
    var type: DeviceType
}
