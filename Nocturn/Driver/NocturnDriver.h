#pragma once

#import <CoreAudio/AudioServerPlugIn.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Entry point invoked by the CoreAudio HAL when the plug-in bundle is loaded.
/// Returns an `AudioServerPlugInDriverInterface` vtable that the HAL uses to
/// drive device lifecycle and IO operations.
///
/// The returned type is `void *` per the CoreAudio header contract; callers
/// cast to `AudioServerPlugInDriverRef`.
void *NocturnDriverFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);

#ifdef __cplusplus
}
#endif
