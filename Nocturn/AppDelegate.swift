import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = AppLogger.app
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let deviceManager = DeviceManager()
    private let audioTapManager = AudioTapManager()
    private lazy var audioEngine = AudioEngine(deviceManager: deviceManager, tapManager: audioTapManager)
    private var globalShortcutMonitor: Any?

    /// Default global shortcut: ⌥⌘N. Stored as a string "modifiers|keycode" in UserDefaults.
    private let shortcutDefaultsKey = "nocturn.globalShortcut"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        installGlobalShortcut()
        Task {
            await audioEngine.refreshNow()
            let allowed = await Permissions.requestMicrophoneAccess()
            await MainActor.run {
                audioEngine.microphonePermissionDenied = !allowed
            }
        }
        logger.info("Nocturn launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            globalShortcutMonitor = nil
        }
        audioTapManager.stopAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 22)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "waveform.and.magnifyingglass",
                accessibilityDescription: "Nocturn"
            )
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
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func installGlobalShortcut() {
        let (modifiers, keyCode) = resolveConfiguredShortcut()
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            if event.keyCode == keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers {
                DispatchQueue.main.async { self.togglePopover(nil) }
            }
        }
    }

    private func resolveConfiguredShortcut() -> (NSEvent.ModifierFlags, UInt16) {
        let stored = UserDefaults.standard.string(forKey: shortcutDefaultsKey)
        if let stored, let parsed = parseShortcut(stored) {
            return parsed
        }
        return ([.option, .command], UInt16(kVK_ANSI_N))
    }

    private func parseShortcut(_ raw: String) -> (NSEvent.ModifierFlags, UInt16)? {
        let parts = raw.split(separator: "|")
        guard parts.count == 2,
              let modsRaw = UInt(parts[0]),
              let keyCode = UInt16(parts[1])
        else { return nil }
        let modifiers = NSEvent.ModifierFlags(rawValue: modsRaw)
        return (modifiers.intersection(.deviceIndependentFlagsMask), keyCode)
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
