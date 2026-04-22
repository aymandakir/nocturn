import AVFoundation
import Foundation
import ServiceManagement

/// Utility namespace for runtime permissions and launch-at-login behavior.
enum Permissions {
    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func microphoneStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func launchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
