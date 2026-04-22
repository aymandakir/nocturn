import Foundation
import CoreAudio

/// CoreAudio and Nocturn audio-flow errors.
enum AudioError: LocalizedError {
    case propertyReadFailed(OSStatus)
    case propertyWriteFailed(OSStatus)
    case deviceNotFound
    case streamConfigurationFailed
    case tapUnavailable
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case let .propertyReadFailed(status):
            return "Failed to read CoreAudio property (\(status))."
        case let .propertyWriteFailed(status):
            return "Failed to write CoreAudio property (\(status))."
        case .deviceNotFound:
            return "Audio device not found."
        case .streamConfigurationFailed:
            return "Failed to configure the audio stream."
        case .tapUnavailable:
            return "AudioTap is unavailable on this system."
        case .unsupportedOS:
            return "This operation requires a newer macOS version."
        }
    }
}
