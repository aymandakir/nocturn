import CoreAudio
import Foundation
import Observation

@Observable
final class DeviceManager {
    var outputDevices: [AudioDevice] = []
    var inputDevices: [AudioDevice] = []
    var defaultOutput: AudioDevice?
    var defaultInput: AudioDevice?
    var globalOutputVolume: Float = 1.0

    private let logger = AppLogger.audio
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue(label: "com.aymandakir.nocturn.device-listeners")

    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    init() {
        installListeners()
        Task { await refresh() }
    }

    deinit {
        removeListeners()
    }

    func refresh() async {
        do {
            let ids: [AudioDeviceID] = try getPropertyDataArray(
                systemObjectID,
                address: CoreAudioProperty.devices,
                elementType: AudioDeviceID.self
            )
            let allDevices = ids.compactMap { try? buildDevice(from: $0) }
            outputDevices = allDevices.filter(\.isOutput).sorted { $0.name < $1.name }
            inputDevices = allDevices.filter(\.isInput).sorted { $0.name < $1.name }
            defaultOutput = try currentDefaultOutput()
            defaultInput = try currentDefaultInput()
            globalOutputVolume = try readGlobalOutputVolume()

            for device in allDevices {
                logger.info("Discovered device: \(device.name, privacy: .public) [\(device.uid, privacy: .public)]")
            }
        } catch {
            logger.error("Device refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setDefaultOutput(_ device: AudioDevice) async throws {
        try setPropertyData(systemObjectID, address: CoreAudioProperty.defaultOutputDevice, value: device.id)
        await refresh()
    }

    func setDefaultInput(_ device: AudioDevice) async throws {
        try setPropertyData(systemObjectID, address: CoreAudioProperty.defaultInputDevice, value: device.id)
        await refresh()
    }

    func setGlobalOutputVolume(_ value: Float) {
        guard let defaultOutput else { return }
        do {
            try setPropertyData(defaultOutput.id, address: CoreAudioProperty.virtualMainVolume, value: value)
            globalOutputVolume = value
        } catch {
            logger.error("Failed setting global output volume: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readGlobalOutputVolume() throws -> Float {
        guard let defaultOutput else { return 1.0 }
        return try getPropertyData(defaultOutput.id, address: CoreAudioProperty.virtualMainVolume, defaultValue: Float(1.0))
    }

    private func currentDefaultOutput() throws -> AudioDevice? {
        let id: AudioDeviceID = try getPropertyData(
            systemObjectID,
            address: CoreAudioProperty.defaultOutputDevice,
            defaultValue: AudioDeviceID(0)
        )
        return try? buildDevice(from: id)
    }

    private func currentDefaultInput() throws -> AudioDevice? {
        let id: AudioDeviceID = try getPropertyData(
            systemObjectID,
            address: CoreAudioProperty.defaultInputDevice,
            defaultValue: AudioDeviceID(0)
        )
        return try? buildDevice(from: id)
    }

    private func buildDevice(from id: AudioDeviceID) throws -> AudioDevice {
        let name = try readCFStringProperty(objectID: id, address: CoreAudioProperty.deviceName) ?? "Unknown Device"
        let uid = try readCFStringProperty(objectID: id, address: CoreAudioProperty.deviceUID) ?? "\(id)"
        let outputStreams: [AudioStreamID] = (try? getPropertyDataArray(id, address: CoreAudioProperty.streamsOutput, elementType: AudioStreamID.self)) ?? []
        let inputStreams: [AudioStreamID] = (try? getPropertyDataArray(id, address: CoreAudioProperty.streamsInput, elementType: AudioStreamID.self)) ?? []

        return AudioDevice(
            id: id,
            name: name,
            uid: uid,
            isInput: !inputStreams.isEmpty,
            isOutput: !outputStreams.isEmpty,
            type: inferDeviceType(name: name, uid: uid)
        )
    }

    private func readCFStringProperty(objectID: AudioObjectID, address: AudioObjectPropertyAddress) throws -> String? {
        var cfString: CFString = "" as CFString
        var mutableAddress = address
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(objectID, &mutableAddress, 0, nil, &size, &cfString)
        guard status == noErr else {
            throw AudioError.propertyReadFailed(status)
        }
        return cfString as String
    }

    private func inferDeviceType(name: String, uid: String) -> AudioDevice.DeviceType {
        let lowercase = "\(name) \(uid)".lowercased()
        if lowercase.contains("airpods") || lowercase.contains("headphone") {
            return .headphones
        }
        if lowercase.contains("airplay") {
            return .airPlay
        }
        if lowercase.contains("bluetooth") {
            return .bluetooth
        }
        if lowercase.contains("virtual") {
            return .virtual
        }
        if lowercase.contains("speaker") {
            return .speaker
        }
        if lowercase.contains("built-in") || lowercase.contains("macbook") {
            return .builtIn
        }
        return .unknown
    }

    private func installListeners() {
        var devicesAddress = CoreAudioProperty.devices
        var outputAddress = CoreAudioProperty.defaultOutputDevice
        var inputAddress = CoreAudioProperty.defaultInputDevice

        let refreshBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { await self?.refresh() }
        }

        devicesListener = refreshBlock
        defaultOutputListener = refreshBlock
        defaultInputListener = refreshBlock

        if let devicesListener {
            _ = AudioObjectAddPropertyListenerBlock(systemObjectID, &devicesAddress, listenerQueue, devicesListener)
        }
        if let defaultOutputListener {
            _ = AudioObjectAddPropertyListenerBlock(systemObjectID, &outputAddress, listenerQueue, defaultOutputListener)
        }
        if let defaultInputListener {
            _ = AudioObjectAddPropertyListenerBlock(systemObjectID, &inputAddress, listenerQueue, defaultInputListener)
        }
    }

    private func removeListeners() {
        var devicesAddress = CoreAudioProperty.devices
        var outputAddress = CoreAudioProperty.defaultOutputDevice
        var inputAddress = CoreAudioProperty.defaultInputDevice

        if let devicesListener {
            _ = AudioObjectRemovePropertyListenerBlock(systemObjectID, &devicesAddress, listenerQueue, devicesListener)
        }
        if let defaultOutputListener {
            _ = AudioObjectRemovePropertyListenerBlock(systemObjectID, &outputAddress, listenerQueue, defaultOutputListener)
        }
        if let defaultInputListener {
            _ = AudioObjectRemovePropertyListenerBlock(systemObjectID, &inputAddress, listenerQueue, defaultInputListener)
        }
    }
}
