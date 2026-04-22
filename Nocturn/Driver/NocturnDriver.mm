#import "NocturnDriver.h"

#import <CoreAudio/AudioServerPlugIn.h>
#import <CoreFoundation/CoreFoundation.h>
#import <os/log.h>

#include <cstdint>
#include <mutex>
#include <unordered_map>

namespace {

os_log_t NocturnLog() {
    static os_log_t logger = os_log_create("com.aymandakir.nocturn.driver", "driver");
    return logger;
}

// ---- Per-client volume table ------------------------------------------------

std::mutex gVolumeMutex;
std::unordered_map<pid_t, float> gClientVolumes;

float VolumeForClient(pid_t pid) {
    std::lock_guard<std::mutex> lock(gVolumeMutex);
    auto it = gClientVolumes.find(pid);
    return it == gClientVolumes.end() ? 1.0f : it->second;
}

// ---- AudioServerPlugInDriverInterface stubs --------------------------------

HRESULT NocturnDriver_QueryInterface(void *ref, REFIID uuid, LPVOID *outInterface) {
    (void)ref;
    (void)uuid;
    *outInterface = ref;
    return 0;
}

ULONG NocturnDriver_AddRef(void *ref) {
    (void)ref;
    return 1;
}

ULONG NocturnDriver_Release(void *ref) {
    (void)ref;
    return 1;
}

OSStatus NocturnDriver_Initialize(AudioServerPlugInDriverRef driver,
                                  AudioServerPlugInHostRef host) {
    (void)driver;
    (void)host;
    os_log(NocturnLog(), "NocturnDriver Initialize");
    return noErr;
}

OSStatus NocturnDriver_CreateDevice(AudioServerPlugInDriverRef driver,
                                    CFDictionaryRef description,
                                    const AudioServerPlugInClientInfo *clientInfo,
                                    AudioObjectID *outDeviceObjectID) {
    (void)driver;
    (void)description;
    (void)clientInfo;
    *outDeviceObjectID = 0;
    return kAudioHardwareUnsupportedOperationError;
}

OSStatus NocturnDriver_DestroyDevice(AudioServerPlugInDriverRef driver,
                                     AudioObjectID deviceObjectID) {
    (void)driver;
    (void)deviceObjectID;
    return noErr;
}

OSStatus NocturnDriver_AddDeviceClient(AudioServerPlugInDriverRef driver,
                                       AudioObjectID deviceObjectID,
                                       const AudioServerPlugInClientInfo *clientInfo) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientInfo;
    return noErr;
}

OSStatus NocturnDriver_RemoveDeviceClient(AudioServerPlugInDriverRef driver,
                                          AudioObjectID deviceObjectID,
                                          const AudioServerPlugInClientInfo *clientInfo) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientInfo;
    return noErr;
}

OSStatus NocturnDriver_PerformConfigurationChange(AudioServerPlugInDriverRef driver,
                                                  AudioObjectID objectID,
                                                  UInt64 changeAction,
                                                  void *changeInfo) {
    (void)driver;
    (void)objectID;
    (void)changeAction;
    (void)changeInfo;
    return noErr;
}

OSStatus NocturnDriver_AbortConfigurationChange(AudioServerPlugInDriverRef driver,
                                                AudioObjectID objectID,
                                                UInt64 changeAction,
                                                void *changeInfo) {
    (void)driver;
    (void)objectID;
    (void)changeAction;
    (void)changeInfo;
    return noErr;
}

OSStatus NocturnDriver_HasProperty(AudioServerPlugInDriverRef driver,
                                   AudioObjectID objectID,
                                   pid_t clientProcessID,
                                   const AudioObjectPropertyAddress *address,
                                   Boolean *outHasProperty) {
    (void)driver;
    (void)objectID;
    (void)clientProcessID;
    (void)address;
    *outHasProperty = false;
    return noErr;
}

OSStatus NocturnDriver_IsPropertySettable(AudioServerPlugInDriverRef driver,
                                          AudioObjectID objectID,
                                          pid_t clientProcessID,
                                          const AudioObjectPropertyAddress *address,
                                          Boolean *outIsSettable) {
    (void)driver;
    (void)objectID;
    (void)clientProcessID;
    (void)address;
    *outIsSettable = false;
    return noErr;
}

OSStatus NocturnDriver_GetPropertyDataSize(AudioServerPlugInDriverRef driver,
                                           AudioObjectID objectID,
                                           pid_t clientProcessID,
                                           const AudioObjectPropertyAddress *address,
                                           UInt32 qualifierDataSize,
                                           const void *qualifierData,
                                           UInt32 *outDataSize) {
    (void)driver;
    (void)objectID;
    (void)clientProcessID;
    (void)address;
    (void)qualifierDataSize;
    (void)qualifierData;
    *outDataSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

OSStatus NocturnDriver_GetPropertyData(AudioServerPlugInDriverRef driver,
                                       AudioObjectID objectID,
                                       pid_t clientProcessID,
                                       const AudioObjectPropertyAddress *address,
                                       UInt32 qualifierDataSize,
                                       const void *qualifierData,
                                       UInt32 dataSize,
                                       UInt32 *dataUsedSize,
                                       void *outData) {
    (void)driver;
    (void)objectID;
    (void)clientProcessID;
    (void)address;
    (void)qualifierDataSize;
    (void)qualifierData;
    (void)dataSize;
    (void)outData;
    *dataUsedSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

OSStatus NocturnDriver_SetPropertyData(AudioServerPlugInDriverRef driver,
                                       AudioObjectID objectID,
                                       pid_t clientProcessID,
                                       const AudioObjectPropertyAddress *address,
                                       UInt32 qualifierDataSize,
                                       const void *qualifierData,
                                       UInt32 dataSize,
                                       const void *data) {
    (void)driver;
    (void)objectID;
    (void)clientProcessID;
    (void)address;
    (void)qualifierDataSize;
    (void)qualifierData;
    (void)dataSize;
    (void)data;
    return kAudioHardwareUnsupportedOperationError;
}

OSStatus NocturnDriver_StartIO(AudioServerPlugInDriverRef driver,
                               AudioObjectID deviceObjectID,
                               UInt32 clientID) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientID;
    return noErr;
}

OSStatus NocturnDriver_StopIO(AudioServerPlugInDriverRef driver,
                              AudioObjectID deviceObjectID,
                              UInt32 clientID) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientID;
    return noErr;
}

OSStatus NocturnDriver_GetZeroTimeStamp(AudioServerPlugInDriverRef driver,
                                        AudioObjectID deviceObjectID,
                                        UInt32 clientID,
                                        Float64 *outSampleTime,
                                        UInt64 *outHostTime,
                                        UInt64 *outSeed) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientID;
    *outSampleTime = 0.0;
    *outHostTime = 0;
    *outSeed = 0;
    return noErr;
}

OSStatus NocturnDriver_WillDoIOOperation(AudioServerPlugInDriverRef driver,
                                         AudioObjectID deviceObjectID,
                                         UInt32 clientID,
                                         UInt32 operationID,
                                         Boolean *outWillDo,
                                         Boolean *outWillDoInPlace) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientID;
    (void)operationID;
    *outWillDo = false;
    *outWillDoInPlace = true;
    return noErr;
}

OSStatus NocturnDriver_BeginIOOperation(AudioServerPlugInDriverRef driver,
                                        AudioObjectID deviceObjectID,
                                        UInt32 clientID,
                                        UInt32 operationID,
                                        UInt32 ioBufferFrameSize,
                                        const AudioServerPlugInIOCycleInfo *cycleInfo) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientID;
    (void)operationID;
    (void)ioBufferFrameSize;
    (void)cycleInfo;
    return noErr;
}

OSStatus NocturnDriver_DoIOOperation(AudioServerPlugInDriverRef driver,
                                     AudioObjectID deviceObjectID,
                                     AudioObjectID streamObjectID,
                                     UInt32 clientID,
                                     UInt32 operationID,
                                     UInt32 ioBufferFrameSize,
                                     const AudioServerPlugInIOCycleInfo *cycleInfo,
                                     void *ioMainBuffer,
                                     void *ioSecondaryBuffer) {
    (void)driver;
    (void)deviceObjectID;
    (void)streamObjectID;
    (void)clientID;
    (void)operationID;
    (void)ioBufferFrameSize;
    (void)cycleInfo;
    (void)ioMainBuffer;
    (void)ioSecondaryBuffer;
    return noErr;
}

OSStatus NocturnDriver_EndIOOperation(AudioServerPlugInDriverRef driver,
                                      AudioObjectID deviceObjectID,
                                      UInt32 clientID,
                                      UInt32 operationID,
                                      UInt32 ioBufferFrameSize,
                                      const AudioServerPlugInIOCycleInfo *cycleInfo) {
    (void)driver;
    (void)deviceObjectID;
    (void)clientID;
    (void)operationID;
    (void)ioBufferFrameSize;
    (void)cycleInfo;
    return noErr;
}

AudioServerPlugInDriverInterface gNocturnDriverInterface = {
    nullptr,
    NocturnDriver_QueryInterface,
    NocturnDriver_AddRef,
    NocturnDriver_Release,
    NocturnDriver_Initialize,
    NocturnDriver_CreateDevice,
    NocturnDriver_DestroyDevice,
    NocturnDriver_AddDeviceClient,
    NocturnDriver_RemoveDeviceClient,
    NocturnDriver_PerformConfigurationChange,
    NocturnDriver_AbortConfigurationChange,
    NocturnDriver_HasProperty,
    NocturnDriver_IsPropertySettable,
    NocturnDriver_GetPropertyDataSize,
    NocturnDriver_GetPropertyData,
    NocturnDriver_SetPropertyData,
    NocturnDriver_StartIO,
    NocturnDriver_StopIO,
    NocturnDriver_GetZeroTimeStamp,
    NocturnDriver_WillDoIOOperation,
    NocturnDriver_BeginIOOperation,
    NocturnDriver_DoIOOperation,
    NocturnDriver_EndIOOperation,
};

AudioServerPlugInDriverInterface *gNocturnDriverInterfacePtr = &gNocturnDriverInterface;

}  // namespace

extern "C" void *NocturnDriverFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    (void)allocator;
    if (requestedTypeUUID == nullptr) {
        return nullptr;
    }
    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }
    return &gNocturnDriverInterfacePtr;
}

extern "C" void NocturnDriver_SetClientVolume(pid_t pid, float volume) {
    std::lock_guard<std::mutex> lock(gVolumeMutex);
    gClientVolumes[pid] = volume;
}

extern "C" float NocturnDriver_GetClientVolume(pid_t pid) {
    return VolumeForClient(pid);
}
