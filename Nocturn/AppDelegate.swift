import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = AppLogger.app
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let deviceManager = DeviceManager()
    private let audioTapManager = AudioTapManager()
    private lazy var audioEngine = AudioEngine(deviceManager: deviceManager, tapManager: audioTapManager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        Task {
            await audioEngine.refreshNow()
            let allowed = await Permissions.requestMicrophoneAccess()
            await MainActor.run {
                audioEngine.microphonePermissionDenied = !allowed
            }
        }
        logger.info("Nocturn launched")
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 22)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.and.magnifyingglass", accessibilityDescription: "Nocturn")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 360, height: 600)
        popover.behavior = .transient
        let rootView = MenuBarView()
            .environment(\.audioEngine, audioEngine)
            .environment(\.audioTapManager, audioTapManager)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
