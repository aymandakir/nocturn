import CoreAudio
import Foundation

enum CoreAudioProperty {
    static let devices = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let defaultOutputDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let defaultInputDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let deviceName = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let deviceUID = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let streamsOutput = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static let streamsInput = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    static let processObjectList = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let processPID = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let processIsRunning = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunning,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static let virtualMainVolume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
}

/// Reads a single CoreAudio property value.
func getPropertyData<T>(
    _ objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    defaultValue: T
) throws -> T {
    var mutableAddress = address
    var value = defaultValue
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(objectID, &mutableAddress, 0, nil, &size, &value)
    guard status == noErr else {
        throw AudioError.propertyReadFailed(status)
    }
    return value
}

/// Writes a single CoreAudio property value.
func setPropertyData<T>(
    _ objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    value: T
) throws {
    var mutableAddress = address
    var mutableValue = value
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectSetPropertyData(objectID, &mutableAddress, 0, nil, size, &mutableValue)
    guard status == noErr else {
        throw AudioError.propertyWriteFailed(status)
    }
}

/// Reads a variable-size CoreAudio property as a typed array.
func getPropertyDataArray<T>(
    _ objectID: AudioObjectID,
    address: AudioObjectPropertyAddress,
    elementType: T.Type = T.self
) throws -> [T] {
    _ = elementType
    var mutableAddress = address
    var byteCount: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(objectID, &mutableAddress, 0, nil, &byteCount)
    guard status == noErr else {
        throw AudioError.propertyReadFailed(status)
    }
    let elementCount = Int(byteCount) / MemoryLayout<T>.size
    var values = [T](unsafeUninitializedCapacity: elementCount) { _, initializedCount in
        initializedCount = elementCount
    }
    status = AudioObjectGetPropertyData(objectID, &mutableAddress, 0, nil, &byteCount, &values)
    guard status == noErr else {
        throw AudioError.propertyReadFailed(status)
    }
    return values
}
