import AVFoundation
import Foundation
import ServiceManagement

/// Utility namespace for runtime permissions plus the HAL driver install/
/// uninstall flow.
enum Permissions {
    /// Filesystem path where macOS expects HAL plug-ins.
    static let driverInstallDirectory = "/Library/Audio/Plug-Ins/HAL"

    /// Bundle name written to the HAL plug-ins directory once installed.
    static let driverBundleName = "NocturnDriver.driver"

    /// Present status for the HAL driver in the filesystem.
    enum DriverState: Equatable {
        case notInstalled
        case installed(version: String)
        case updateAvailable(installed: String, latest: String)
    }

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

    /// Inspects `/Library/Audio/Plug-Ins/HAL/NocturnDriver.driver` and compares
    /// its version to the app bundle's packaged driver.
    static func driverState(latestVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") -> DriverState {
        let installedPath = "\(driverInstallDirectory)/\(driverBundleName)"
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: installedPath) else {
            return .notInstalled
        }
        let plistURL = URL(fileURLWithPath: "\(installedPath)/Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let installed = plist["CFBundleShortVersionString"] as? String
        else {
            return .updateAvailable(installed: "unknown", latest: latestVersion)
        }
        if installed == latestVersion {
            return .installed(version: installed)
        }
        return .updateAvailable(installed: installed, latest: latestVersion)
    }

    /// Installs the packaged driver bundle into the HAL plug-ins directory and
    /// restarts `coreaudiod`. Requires administrator privileges. The install
    /// is performed via `osascript`-driven `cp`/`launchctl` until a privileged
    /// helper tool is bundled (tracked separately).
    static func installDriver() throws {
        guard let packaged = packagedDriverURL() else {
            throw NSError(
                domain: "com.aymandakir.nocturn",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled driver not found."]
            )
        }
        let destination = "\(driverInstallDirectory)/\(driverBundleName)"
        let source = packaged.path
        let script = """
        do shell script "mkdir -p '\(driverInstallDirectory)' && \\
        rm -rf '\(destination)' && \\
        cp -R '\(source)' '\(destination)' && \\
        launchctl kickstart -k system/com.apple.audio.coreaudiod" \
        with administrator privileges
        """
        try runAppleScript(script)
    }

    /// Removes the installed driver bundle and restarts `coreaudiod`.
    static func uninstallDriver() throws {
        let destination = "\(driverInstallDirectory)/\(driverBundleName)"
        let script = """
        do shell script "rm -rf '\(destination)' && \\
        launchctl kickstart -k system/com.apple.audio.coreaudiod" \
        with administrator privileges
        """
        try runAppleScript(script)
    }

    private static func packagedDriverURL() -> URL? {
        if let bundleURL = Bundle.main.url(
            forResource: "NocturnDriver",
            withExtension: "driver"
        ) {
            return bundleURL
        }
        return Bundle.main.builtInPlugInsURL?.appendingPathComponent("NocturnDriver.driver")
    }

    private static func runAppleScript(_ source: String) throws {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NSError(
                domain: "com.aymandakir.nocturn",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create AppleScript."]
            )
        }
        script.executeAndReturnError(&errorDict)
        if let errorDict {
            let message = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw NSError(
                domain: "com.aymandakir.nocturn",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
