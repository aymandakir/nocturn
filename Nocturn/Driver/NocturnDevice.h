#pragma once

#import <Foundation/Foundation.h>

/// Identifier of the "Nocturn" virtual audio device exposed by the HAL plug-in.
/// Used to look the device up via CoreAudio UID queries.
extern NSString *const NocturnDeviceUID;
