#import <AudioToolbox/AudioHardwareService.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>

#include <bootstrap.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <mach/mach.h>
#include <mach/message.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const NSUInteger kMaxCacheBytes = 64 * 1024;
static const NSUInteger kMaxCacheLineBytes = 4 * 1024;
static const NSUInteger kMaxPayloadBytes = 16 * 1024;
static const NSUInteger kMaxTokenBytes = 1024;
static const NSUInteger kMaxArguments = 64;
static const mach_msg_timeout_t kMachSendTimeoutMilliseconds = 50;
static const mach_msg_timeout_t kMachReceiveTimeoutMilliseconds = 150;

enum { kMaxAudioChannels = 32 };

struct barista_mach_message {
  mach_msg_header_t header;
  mach_msg_size_t descriptorCount;
  mach_msg_ool_descriptor_t descriptor;
};

struct barista_mach_buffer {
  struct barista_mach_message message;
  mach_msg_trailer_t trailer;
};

static NSString *environment_value(NSString *name) {
  NSString *value = NSProcessInfo.processInfo.environment[name];
  return value.length > 0 ? value : nil;
}

static NSString *first_environment_value(NSArray<NSString *> *names) {
  for (NSString *name in names) {
    NSString *value = environment_value(name);
    if (value.length > 0) {
      return value;
    }
  }
  return nil;
}

static BOOL parse_bool_strict(NSString *value, BOOL *result) {
  if (value.length == 0) {
    return NO;
  }
  NSString *normalized = value.lowercaseString;
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"]
      || [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    if (result) *result = YES;
    return YES;
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"]
      || [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    if (result) *result = NO;
    return YES;
  }
  return NO;
}

static BOOL parse_integer_strict(NSString *value,
                                 NSInteger minimum,
                                 NSInteger maximum,
                                 NSInteger *result) {
  if (value.length == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  NSInteger parsed = 0;
  if (![scanner scanInteger:&parsed] || !scanner.isAtEnd
      || parsed < minimum || parsed > maximum) {
    return NO;
  }
  if (result) *result = parsed;
  return YES;
}

static NSString *normalize_value(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || value.length == 0) {
    return @"";
  }

  NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
  NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
  __block BOOL lastWasSpace = YES;
  [value enumerateSubstringsInRange:NSMakeRange(0, value.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *substring,
                                      NSRange substringRange,
                                      NSRange enclosingRange,
                                      BOOL *stop) {
    (void)substringRange;
    (void)enclosingRange;
    (void)stop;
    BOOL replaceWithSpace = NO;
    for (NSUInteger index = 0; index < substring.length; index++) {
      unichar character = [substring characterAtIndex:index];
      if (character == 0 || [whitespace characterIsMember:character]
          || character <= 0x1f || (character >= 0x7f && character <= 0x9f)) {
        replaceWithSpace = YES;
        break;
      }
    }
    if (replaceWithSpace) {
      if (!lastWasSpace && result.length > 0) {
        [result appendString:@" "];
        lastWasSpace = YES;
      }
      return;
    }
    [result appendString:substring];
    lastWasSpace = NO;
  }];
  return [result stringByTrimmingCharactersInSet:whitespace];
}

static NSString *truncate_value(NSString *value,
                                NSUInteger maximumCharacters,
                                NSUInteger maximumBytes) {
  if (value.length == 0 || maximumCharacters == 0 || maximumBytes == 0) {
    return @"";
  }

  NSUInteger byteLength = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  __block NSUInteger characterCount = 0;
  [value enumerateSubstringsInRange:NSMakeRange(0, value.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *substring,
                                      NSRange substringRange,
                                      NSRange enclosingRange,
                                      BOOL *stop) {
    (void)substring;
    (void)substringRange;
    (void)enclosingRange;
    (void)stop;
    characterCount++;
  }];
  if (characterCount <= maximumCharacters && byteLength <= maximumBytes) {
    return value;
  }

  NSString *ellipsis = @"…";
  NSUInteger ellipsisBytes = [ellipsis lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  NSUInteger targetCharacters = maximumCharacters > 1 ? maximumCharacters - 1 : 0;
  NSUInteger targetBytes = maximumBytes > ellipsisBytes ? maximumBytes - ellipsisBytes : 0;
  NSMutableString *result = [NSMutableString string];
  __block NSUInteger usedCharacters = 0;
  __block NSUInteger usedBytes = 0;
  [value enumerateSubstringsInRange:NSMakeRange(0, value.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *substring,
                                      NSRange substringRange,
                                      NSRange enclosingRange,
                                      BOOL *stop) {
    (void)substringRange;
    (void)enclosingRange;
    NSUInteger bytes = [substring lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (usedCharacters >= targetCharacters || usedBytes + bytes > targetBytes) {
      *stop = YES;
      return;
    }
    [result appendString:substring];
    usedCharacters++;
    usedBytes += bytes;
  }];
  if (maximumCharacters >= 1 && maximumBytes >= ellipsisBytes) {
    [result appendString:ellipsis];
  }
  return result;
}

static NSString *sanitize_value(NSString *value,
                                NSUInteger maximumCharacters,
                                NSUInteger maximumBytes) {
  return truncate_value(normalize_value(value), maximumCharacters, maximumBytes);
}

static NSString *property(NSString *name,
                          NSString *value,
                          NSUInteger maximumCharacters,
                          NSUInteger maximumBytes) {
  return [NSString stringWithFormat:@"%@=%@",
                                    name,
                                    sanitize_value(value, maximumCharacters, maximumBytes)];
}

static NSString *default_config_dir(void) {
  NSString *configured = first_environment_value(@[@"BARISTA_CONFIG_DIR", @"CONFIG_DIR"]);
  return configured ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar"];
}

static NSString *runtime_cache_dir(void) {
  NSString *configured = first_environment_value(@[
    @"BARISTA_VOLUME_CACHE_DIR",
    @"BARISTA_RUNTIME_CONTEXT_DIR",
  ]);
  if (configured.length > 0) {
    return configured.stringByStandardizingPath;
  }
  return [[[default_config_dir() stringByAppendingPathComponent:@"cache"]
    stringByAppendingPathComponent:@"runtime_context"] stringByStandardizingPath];
}

static NSString *bounded_file_contents(NSString *path, BOOL *invalid) {
  if (invalid) *invalid = NO;
  if (path.length == 0) {
    return nil;
  }
  int descriptor = open(path.fileSystemRepresentation,
                        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (descriptor < 0) {
    if (errno != ENOENT && invalid) *invalid = YES;
    return nil;
  }

  struct stat status = {0};
  if (fstat(descriptor, &status) != 0 || !S_ISREG(status.st_mode)
      || status.st_size < 0 || (uint64_t)status.st_size > kMaxCacheBytes) {
    close(descriptor);
    if (invalid) *invalid = YES;
    return nil;
  }

  char *buffer = malloc(kMaxCacheBytes + 1);
  if (!buffer) {
    close(descriptor);
    if (invalid) *invalid = YES;
    return nil;
  }
  size_t used = 0;
  while (used <= kMaxCacheBytes) {
    ssize_t count = read(descriptor, buffer + used, kMaxCacheBytes + 1 - used);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count < 0) {
      used = kMaxCacheBytes + 1;
      break;
    }
    if (count == 0) {
      break;
    }
    used += (size_t)count;
  }
  close(descriptor);
  if (used > kMaxCacheBytes) {
    free(buffer);
    if (invalid) *invalid = YES;
    return nil;
  }

  size_t lineBytes = 0;
  for (size_t index = 0; index < used; index++) {
    if (buffer[index] == '\0') {
      free(buffer);
      if (invalid) *invalid = YES;
      return nil;
    }
    if (buffer[index] == '\n') {
      lineBytes = 0;
      continue;
    }
    lineBytes++;
    if (lineBytes > kMaxCacheLineBytes) {
      free(buffer);
      if (invalid) *invalid = YES;
      return nil;
    }
  }

  NSString *contents = [[NSString alloc] initWithBytes:buffer
                                                length:used
                                              encoding:NSUTF8StringEncoding];
  free(buffer);
  if (!contents && invalid) *invalid = YES;
  return contents;
}

static NSDictionary<NSString *, NSString *> *read_media_cache(NSString *path, BOOL *invalid) {
  NSString *contents = bounded_file_contents(path, invalid);
  if (contents.length == 0) {
    return @{};
  }
  NSSet<NSString *> *accepted = [NSSet setWithArray:@[
    @"player", @"state", @"track", @"artist", @"toggle_label", @"toggle_icon",
    @"current_output",
  ]];
  NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
  [contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
    (void)stop;
    NSRange separator = [line rangeOfString:@"\t"];
    if (separator.location == NSNotFound) {
      return;
    }
    NSString *key = [line substringToIndex:separator.location];
    if (![accepted containsObject:key] || values[key] != nil) {
      return;
    }
    values[key] = [line substringFromIndex:NSMaxRange(separator)];
  }];
  return values;
}

static NSArray<id> *read_outputs_cache(NSString *path, BOOL *invalid) {
  NSString *contents = bounded_file_contents(path, invalid);
  NSMutableArray<id> *rows = [NSMutableArray arrayWithObjects:
    NSNull.null, NSNull.null, NSNull.null, NSNull.null, nil];
  if (contents.length == 0) {
    return rows;
  }

  [contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
    (void)stop;
    NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
    if (fields.count != 4 || ![fields[0] isEqualToString:@"output"]) {
      return;
    }
    NSInteger index = 0;
    if (!parse_integer_strict(fields[1], 1, 4, &index)
        || (![fields[2] isEqualToString:@"true"]
            && ![fields[2] isEqualToString:@"false"])
        || rows[(NSUInteger)index - 1] != NSNull.null) {
      return;
    }
    BOOL selected = [fields[2] isEqualToString:@"true"];
    NSString *name = sanitize_value(fields[3], 96, 256);
    if (name.length == 0) {
      return;
    }
    rows[(NSUInteger)index - 1] = @{
      @"name": name,
      @"selected": selected ? @"true" : @"false",
    };
  }];
  return rows;
}

static BOOL switch_audio_source_available(void) {
  NSString *configured = environment_value(@"BARISTA_SWITCH_AUDIO_SOURCE_BIN");
  NSFileManager *manager = NSFileManager.defaultManager;
  if (configured.length > 0) {
    return [manager isExecutableFileAtPath:configured.stringByStandardizingPath];
  }
  NSString *path = environment_value(@"PATH") ?: @"";
  for (NSString *directory in [path componentsSeparatedByString:@":"]) {
    if (directory.length == 0) continue;
    NSString *candidate = [directory stringByAppendingPathComponent:@"SwitchAudioSource"];
    if ([manager isExecutableFileAtPath:candidate]) {
      return YES;
    }
  }
  for (NSString *candidate in @[
         @"/opt/homebrew/bin/SwitchAudioSource",
         @"/usr/local/bin/SwitchAudioSource",
       ]) {
    if ([manager isExecutableFileAtPath:candidate]) {
      return YES;
    }
  }
  return NO;
}

static BOOL read_float_property(AudioDeviceID device,
                                AudioObjectPropertySelector selector,
                                AudioObjectPropertyElement element,
                                Float32 *value,
                                BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    selector,
    kAudioDevicePropertyScopeOutput,
    element,
  };
  if (!AudioObjectHasProperty(device, &address)) {
    return NO;
  }
  UInt32 size = sizeof(*value);
  OSStatus result = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, value);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  return result == noErr && size == sizeof(*value) && isfinite(*value);
}

static BOOL read_virtual_main_volume(AudioDeviceID device,
                                     Float32 *value,
                                     BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
    kAudioDevicePropertyScopeOutput,
    kAudioObjectPropertyElementMain,
  };
  if (!AudioObjectHasProperty(device, &address)) {
    return NO;
  }
  UInt32 size = sizeof(*value);
  OSStatus result = AudioObjectGetPropertyData(
    device, &address, 0, NULL, &size, value);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  return result == noErr && size == sizeof(*value) && isfinite(*value);
}

static BOOL read_uint32_property(AudioDeviceID device,
                                 AudioObjectPropertySelector selector,
                                 AudioObjectPropertyElement element,
                                 UInt32 *value,
                                 BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    selector,
    kAudioDevicePropertyScopeOutput,
    element,
  };
  if (!AudioObjectHasProperty(device, &address)) {
    return NO;
  }
  UInt32 size = sizeof(*value);
  OSStatus result = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, value);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  return result == noErr && size == sizeof(*value);
}

static BOOL read_default_output_device(AudioDeviceID *device, BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    kAudioHardwarePropertyDefaultOutputDevice,
    kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMain,
  };
  UInt32 size = sizeof(*device);
  OSStatus result = AudioObjectGetPropertyData(
    kAudioObjectSystemObject, &address, 0, NULL, &size, device);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  return result == noErr && size == sizeof(*device) && *device != kAudioObjectUnknown;
}

static NSUInteger preferred_output_channels(AudioDeviceID device,
                                            AudioObjectPropertyElement channels[2],
                                            BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    kAudioDevicePropertyPreferredChannelsForStereo,
    kAudioDevicePropertyScopeOutput,
    kAudioObjectPropertyElementMain,
  };
  if (!AudioObjectHasProperty(device, &address)) {
    return 0;
  }
  UInt32 rawChannels[2] = {0, 0};
  UInt32 size = sizeof(rawChannels);
  OSStatus result = AudioObjectGetPropertyData(
    device, &address, 0, NULL, &size, rawChannels);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  if (result != noErr || size != sizeof(rawChannels)) {
    return 0;
  }
  NSUInteger count = 0;
  for (NSUInteger index = 0; index < 2; index++) {
    if (rawChannels[index] == 0 || (count == 1 && channels[0] == rawChannels[index])) {
      continue;
    }
    channels[count++] = rawChannels[index];
  }
  return count;
}

static NSUInteger output_channel_count(AudioDeviceID device, BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    kAudioDevicePropertyStreamConfiguration,
    kAudioDevicePropertyScopeOutput,
    kAudioObjectPropertyElementMain,
  };
  if (!AudioObjectHasProperty(device, &address)) {
    return 0;
  }

  UInt32 size = 0;
  OSStatus result = AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  if (result != noErr || size < offsetof(AudioBufferList, mBuffers)
      || size > kMaxCacheBytes) {
    return 0;
  }

  AudioBufferList *buffers = calloc(1, size);
  if (!buffers) {
    return 0;
  }
  result = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, buffers);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  if (result != noErr) {
    free(buffers);
    return 0;
  }

  NSUInteger maximumBuffers = (size - offsetof(AudioBufferList, mBuffers))
    / sizeof(AudioBuffer);
  if (buffers->mNumberBuffers > maximumBuffers) {
    free(buffers);
    return 0;
  }

  NSUInteger count = 0;
  for (UInt32 index = 0; index < buffers->mNumberBuffers; index++) {
    count += buffers->mBuffers[index].mNumberChannels;
    if (count >= kMaxAudioChannels) {
      count = kMaxAudioChannels;
      break;
    }
  }
  free(buffers);
  return count;
}

static BOOL channel_was_read(AudioObjectPropertyElement channel,
                             AudioObjectPropertyElement channels[kMaxAudioChannels],
                             NSUInteger count) {
  for (NSUInteger index = 0; index < count; index++) {
    if (channels[index] == channel) {
      return YES;
    }
  }
  return NO;
}

static BOOL read_output_volume(AudioDeviceID device, NSInteger *volume, BOOL *badDevice) {
  Float32 scalar = 0.0f;
  if (read_virtual_main_volume(device, &scalar, badDevice)
      || read_float_property(device,
                             kAudioDevicePropertyVolumeScalar,
                             kAudioObjectPropertyElementMain,
                             &scalar,
                             badDevice)) {
    scalar = fmaxf(0.0f, fminf(1.0f, scalar));
    *volume = (NSInteger)llroundf(scalar * 100.0f);
    return YES;
  }

  Float32 total = 0.0f;
  NSUInteger count = 0;
  AudioObjectPropertyElement readChannels[kMaxAudioChannels] = {0};
  AudioObjectPropertyElement preferredChannels[2] = {0, 0};
  NSUInteger preferredCount = preferred_output_channels(device, preferredChannels, badDevice);
  for (NSUInteger index = 0; index < preferredCount; index++) {
    if (read_float_property(device,
                            kAudioDevicePropertyVolumeScalar,
                            preferredChannels[index],
                            &scalar,
                            badDevice)) {
      total += fmaxf(0.0f, fminf(1.0f, scalar));
      if (count < kMaxAudioChannels) {
        readChannels[count++] = preferredChannels[index];
      }
    }
  }
  if (count > 0) {
    *volume = (NSInteger)llroundf((total / (Float32)count) * 100.0f);
    return YES;
  }

  NSUInteger channelCount = output_channel_count(device, badDevice);
  for (AudioObjectPropertyElement channel = 1; channel <= channelCount; channel++) {
    if (count >= kMaxAudioChannels) {
      break;
    }
    if (channel_was_read(channel, readChannels, count)) {
      continue;
    }
    if (read_float_property(device,
                            kAudioDevicePropertyVolumeScalar,
                            channel,
                            &scalar,
                            badDevice)) {
      total += fmaxf(0.0f, fminf(1.0f, scalar));
      readChannels[count++] = channel;
    }
  }
  if (count == 0) {
    return NO;
  }
  *volume = (NSInteger)llroundf((total / (Float32)count) * 100.0f);
  return YES;
}

static BOOL read_output_muted(AudioDeviceID device, BOOL *muted, BOOL *badDevice) {
  UInt32 value = 0;
  if (read_uint32_property(device,
                           kAudioDevicePropertyMute,
                           kAudioObjectPropertyElementMain,
                           &value,
                           badDevice)) {
    *muted = value != 0;
    return YES;
  }

  BOOL found = NO;
  BOOL allMuted = YES;
  AudioObjectPropertyElement readChannels[kMaxAudioChannels] = {0};
  NSUInteger readCount = 0;
  AudioObjectPropertyElement preferredChannels[2] = {0, 0};
  NSUInteger preferredCount = preferred_output_channels(device, preferredChannels, badDevice);
  for (NSUInteger index = 0; index < preferredCount; index++) {
    if (read_uint32_property(
          device, kAudioDevicePropertyMute, preferredChannels[index], &value, badDevice)) {
      found = YES;
      allMuted = allMuted && value != 0;
      if (readCount < kMaxAudioChannels) {
        readChannels[readCount++] = preferredChannels[index];
      }
    }
  }
  if (found) {
    *muted = allMuted;
    return YES;
  }

  NSUInteger channelCount = output_channel_count(device, badDevice);
  for (AudioObjectPropertyElement channel = 1; channel <= channelCount; channel++) {
    if (readCount >= kMaxAudioChannels) {
      break;
    }
    if (channel_was_read(channel, readChannels, readCount)) {
      continue;
    }
    if (read_uint32_property(
          device, kAudioDevicePropertyMute, channel, &value, badDevice)) {
      found = YES;
      allMuted = allMuted && value != 0;
      readChannels[readCount++] = channel;
    }
  }
  if (found) {
    *muted = allMuted;
  }
  return found;
}

static NSString *read_output_name(AudioDeviceID device, BOOL *badDevice) {
  AudioObjectPropertyAddress address = {
    kAudioObjectPropertyName,
    kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyElementMain,
  };
  if (!AudioObjectHasProperty(device, &address)) {
    return nil;
  }
  CFStringRef name = NULL;
  UInt32 size = sizeof(name);
  OSStatus result = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &name);
  if (result == kAudioHardwareBadDeviceError && badDevice) {
    *badDevice = YES;
  }
  if (result != noErr || size != sizeof(name) || name == NULL) {
    if (name) CFRelease(name);
    return nil;
  }
  NSString *copied = [(__bridge NSString *)name copy];
  CFRelease(name);
  return copied;
}

static BOOL read_audio_state(NSInteger *volume, BOOL *muted, NSString **outputName) {
  for (NSUInteger attempt = 0; attempt < 2; attempt++) {
    BOOL badDevice = NO;
    AudioDeviceID device = kAudioObjectUnknown;
    if (!read_default_output_device(&device, &badDevice)) {
      if (attempt == 0) continue;
      return NO;
    }
    NSInteger currentVolume = 0;
    BOOL currentMuted = NO;
    BOOL hasVolume = read_output_volume(device, &currentVolume, &badDevice);
    BOOL hasMute = read_output_muted(device, &currentMuted, &badDevice);
    NSString *name = read_output_name(device, &badDevice);
    AudioDeviceID confirmedDevice = kAudioObjectUnknown;
    BOOL confirmedBadDevice = NO;
    BOOL stableDevice = read_default_output_device(&confirmedDevice, &confirmedBadDevice)
      && confirmedDevice == device;
    if ((badDevice || confirmedBadDevice || !stableDevice || !hasVolume || !hasMute)
        && attempt == 0) {
      continue;
    }
    if (badDevice || confirmedBadDevice || !stableDevice || !hasVolume || !hasMute) {
      return NO;
    }
    *volume = currentVolume;
    *muted = currentMuted;
    if (outputName) *outputName = name;
    return YES;
  }
  return NO;
}

static NSString *volume_icon(NSInteger volume, BOOL muted) {
  NSString *override = environment_value(@"BARISTA_ICON_VOLUME");
  if (override.length > 0) {
    return sanitize_value(override, 32, 128);
  }
  if (muted || volume == 0) return @"󰖁";
  if (volume >= 60) return @"󰕾";
  if (volume >= 30) return @"󰖀";
  return @"󰕿";
}

static NSString *media_icon(NSDictionary<NSString *, NSString *> *media) {
  NSString *override = environment_value(@"BARISTA_VOLUME_MEDIA_ICON");
  if (override.length > 0) {
    return sanitize_value(override, 32, 128);
  }
  NSString *player = sanitize_value(media[@"player"] ?: @"", 64, 192);
  if ([player caseInsensitiveCompare:@"Spotify"] == NSOrderedSame) return @"";
  if ([player caseInsensitiveCompare:@"Music"] == NSOrderedSame
      || [player caseInsensitiveCompare:@"Apple Music"] == NSOrderedSame) return @"󰎈";
  return player.length > 0 ? @"󰣆" : @"󰎈";
}

static NSString *media_label(NSDictionary<NSString *, NSString *> *media,
                             NSUInteger maximumCharacters) {
  NSString *track = sanitize_value(media[@"track"] ?: @"", 96, 256);
  NSString *artist = sanitize_value(media[@"artist"] ?: @"", 96, 256);
  NSString *player = sanitize_value(media[@"player"] ?: @"", 64, 192);
  NSString *state = sanitize_value(media[@"state"] ?: @"stopped", 32, 96);
  NSString *label = @"Now Playing: Nothing";
  if (track.length > 0 && artist.length > 0) {
    label = [NSString stringWithFormat:@"Now Playing: %@ — %@", track, artist];
  } else if (track.length > 0) {
    label = [NSString stringWithFormat:@"Now Playing: %@", track];
  } else if (player.length > 0) {
    label = [NSString stringWithFormat:@"Now Playing: %@ · %@", player, state];
  }
  return sanitize_value(label, maximumCharacters, 256);
}

static void append_set(NSMutableArray<NSString *> *tokens,
                       NSString *item,
                       NSArray<NSString *> *properties) {
  [tokens addObject:@"--set"];
  [tokens addObject:item];
  [tokens addObjectsFromArray:properties];
}

static NSArray<NSString *> *build_tokens(void) {
  NSInteger volume = 0;
  BOOL muted = NO;
  NSInteger overrideVolume = 0;
  BOOL overrideMuted = NO;
  BOOL hasVolumeOverride = parse_integer_strict(
    first_environment_value(@[@"BARISTA_VOLUME_VALUE", @"BARISTA_VOLUME_OVERRIDE"]),
    0, 100, &overrideVolume);
  BOOL hasMuteOverride = parse_bool_strict(
    first_environment_value(@[@"BARISTA_VOLUME_MUTED", @"BARISTA_MUTE_OVERRIDE"]),
    &overrideMuted);

  NSString *coreAudioOutput = nil;
  if (!hasVolumeOverride || !hasMuteOverride) {
    if (!read_audio_state(&volume, &muted, &coreAudioOutput)) {
      return nil;
    }
  }
  if (hasVolumeOverride) volume = overrideVolume;
  if (hasMuteOverride) muted = overrideMuted;

  NSString *cacheDir = runtime_cache_dir();
  NSString *mediaPath = environment_value(@"BARISTA_MEDIA_CACHE_FILE")
    ?: [cacheDir stringByAppendingPathComponent:@"media.tsv"];
  NSString *outputsPath = environment_value(@"BARISTA_OUTPUTS_CACHE_FILE")
    ?: [cacheDir stringByAppendingPathComponent:@"outputs.tsv"];
  BOOL invalidCache = NO;
  NSDictionary<NSString *, NSString *> *media = read_media_cache(mediaPath, &invalidCache);
  if (invalidCache) {
    media = @{};
  }
  NSArray<id> *outputs = @[NSNull.null, NSNull.null, NSNull.null, NSNull.null];
  if (switch_audio_source_available()) {
    invalidCache = NO;
    outputs = read_outputs_cache(outputsPath, &invalidCache);
    if (invalidCache) {
      outputs = @[NSNull.null, NSNull.null, NSNull.null, NSNull.null];
    }
  }

  NSString *outputOverride = first_environment_value(@[
    @"BARISTA_VOLUME_OUTPUT_NAME", @"BARISTA_OUTPUT_OVERRIDE",
  ]);
  NSString *cachedOutput = sanitize_value(media[@"current_output"] ?: @"", 96, 256);
  NSString *outputName = outputOverride.length > 0
    ? outputOverride
    : (cachedOutput.length > 0 ? cachedOutput : (coreAudioOutput ?: @"System Default"));

  NSString *okColor = sanitize_value(
    environment_value(@"BARISTA_VOLUME_OK") ?: @"0xffa6e3a1", 32, 64);
  NSString *warnColor = sanitize_value(
    environment_value(@"BARISTA_VOLUME_WARN") ?: @"0xfff9e2af", 32, 64);
  NSString *lowColor = sanitize_value(
    environment_value(@"BARISTA_VOLUME_LOW") ?: @"0xfff38ba8", 32, 64);
  NSString *muteColor = sanitize_value(
    environment_value(@"BARISTA_VOLUME_MUTE") ?: @"0xff89b4fa", 32, 64);
  NSString *idleOutputColor = sanitize_value(
    environment_value(@"BARISTA_VOLUME_OUTPUT_IDLE") ?: @"0xffcdd6f4", 32, 64);
  NSString *icon = volume_icon(volume, muted);
  NSString *mainLabel = muted || volume == 0
    ? @"Muted"
    : [NSString stringWithFormat:@"%ld%%", (long)volume];
  NSString *stateLabel = muted
    ? @"Volume: Muted"
    : [NSString stringWithFormat:@"Volume: %ld%%", (long)volume];
  NSString *color = muted || volume == 0
    ? muteColor
    : (volume > 70 ? okColor : (volume > 30 ? warnColor : lowColor));
  NSInteger configuredMediaLimit = 72;
  parse_integer_strict(environment_value(@"BARISTA_MEDIA_LABEL_MAX"),
                       2, 256, &configuredMediaLimit);

  NSMutableArray<NSString *> *tokens = [NSMutableArray array];
  append_set(tokens, @"volume", @[
    property(@"icon", icon, 32, 128),
    property(@"label", mainLabel, 32, 96),
    property(@"icon.color", color, 32, 64),
    property(@"label.color", color, 32, 64),
  ]);
  append_set(tokens, @"volume.state", @[
    property(@"icon", icon, 32, 128),
    property(@"label", stateLabel, 64, 192),
    property(@"icon.color", color, 32, 64),
  ]);
  append_set(tokens, @"volume.output", @[
    property(@"label", [NSString stringWithFormat:@"Output: %@", outputName], 128, 256),
    property(@"icon", @"󰓃", 32, 128),
    property(@"icon.color", okColor, 32, 64),
  ]);

  for (NSUInteger index = 0; index < 4; index++) {
    NSString *item = [NSString stringWithFormat:@"volume.output.%lu",
                                                (unsigned long)index + 1];
    id rawRow = outputs[index];
    if (![rawRow isKindOfClass:[NSDictionary class]]) {
      append_set(tokens, item, @[@"drawing=off", @"label="]);
      continue;
    }
    NSDictionary *row = (NSDictionary *)rawRow;
    BOOL selected = [row[@"selected"] isEqualToString:@"true"];
    NSString *rowColor = selected ? okColor : idleOutputColor;
    NSString *rowLabel = row[@"name"];
    if (selected) rowLabel = [rowLabel stringByAppendingString:@" · Current"];
    append_set(tokens, item, @[
      @"drawing=on",
      property(@"icon", @"󰓃", 32, 128),
      property(@"label", rowLabel, 112, 256),
      property(@"icon.color", rowColor, 32, 64),
      property(@"label.color", rowColor, 32, 64),
    ]);
  }

  append_set(tokens, @"volume.media", @[
    property(@"icon", media_icon(media), 32, 128),
    property(@"label", media_label(media, (NSUInteger)configuredMediaLimit), 256, 256),
    property(@"icon.color", okColor, 32, 64),
  ]);
  append_set(tokens, @"volume.transport.toggle", @[
    property(@"icon", media[@"toggle_icon"] ?: @"󰐊", 32, 128),
    property(@"label", media[@"toggle_label"] ?: @"Play", 48, 128),
  ]);
  append_set(tokens, @"volume.mute", muted ? @[
    property(@"icon", @"󰖁", 32, 128),
    property(@"label", @"Unmute", 32, 96),
  ] : @[
    property(@"icon", @"󰕾", 32, 128),
    property(@"label", @"Mute", 32, 96),
  ]);
  return tokens;
}

static NSData *payload_for_tokens(NSArray<NSString *> *tokens) {
  if (tokens.count == 0 || tokens.count > kMaxArguments) {
    return nil;
  }
  NSMutableData *payload = [NSMutableData data];
  const uint8_t zero = 0;
  for (NSString *token in tokens) {
    NSData *encoded = [token dataUsingEncoding:NSUTF8StringEncoding
                          allowLossyConversion:NO];
    if (!encoded || encoded.length > kMaxTokenBytes
        || memchr(encoded.bytes, 0, encoded.length) != NULL
        || payload.length + encoded.length + 2 > kMaxPayloadBytes) {
      return nil;
    }
    [payload appendData:encoded];
    [payload appendBytes:&zero length:1];
  }
  [payload appendBytes:&zero length:1];
  const uint8_t *bytes = payload.bytes;
  if (payload.length < 2 || bytes[payload.length - 1] != 0
      || bytes[payload.length - 2] != 0) {
    return nil;
  }
  return payload;
}

static mach_port_t sketchybar_port(void) {
  const char *barName = getenv("BAR_NAME");
  if (!barName || barName[0] == '\0' || strlen(barName) > 128) {
    barName = "sketchybar";
  }
  char serviceName[160];
  int written = snprintf(serviceName, sizeof(serviceName), "git.felix.%s", barName);
  if (written < 0 || (size_t)written >= sizeof(serviceName)) {
    return MACH_PORT_NULL;
  }

  mach_port_t bootstrapPort = MACH_PORT_NULL;
  if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &bootstrapPort)
      != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }
  mach_port_t port = MACH_PORT_NULL;
  kern_return_t result = bootstrap_look_up(bootstrapPort, serviceName, &port);
  mach_port_deallocate(mach_task_self(), bootstrapPort);
  if (result != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }
  return port;
}

static BOOL response_is_success(const void *bytes, size_t size) {
  if (!bytes || size == 0 || size > kMaxPayloadBytes) {
    return NO;
  }
  const char *response = bytes;
  if (memchr(response, '\0', size) == NULL) {
    return NO;
  }
  return strstr(response, "[!]") == NULL;
}

static BOOL send_payload(NSData *payload) {
  if (payload.length < 2 || payload.length > kMaxPayloadBytes) {
    return NO;
  }
  const uint8_t *bytes = payload.bytes;
  if (bytes[payload.length - 1] != 0 || bytes[payload.length - 2] != 0) {
    return NO;
  }

  for (NSUInteger attempt = 0; attempt < 2; attempt++) {
    mach_port_t port = sketchybar_port();
    if (port == MACH_PORT_NULL) {
      continue;
    }

    mach_port_t responsePort = MACH_PORT_NULL;
    mach_port_name_t task = mach_task_self();
    if (mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &responsePort) != KERN_SUCCESS) {
      mach_port_deallocate(task, port);
      continue;
    }
    if (mach_port_insert_right(task,
                               responsePort,
                               responsePort,
                               MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
      mach_port_mod_refs(task, responsePort, MACH_PORT_RIGHT_RECEIVE, -1);
      mach_port_deallocate(task, port);
      continue;
    }

    struct barista_mach_message message = {0};
    message.header.msgh_remote_port = port;
    message.header.msgh_local_port = responsePort;
    message.header.msgh_id = responsePort;
    message.header.msgh_bits = MACH_MSGH_BITS_SET(
      MACH_MSG_TYPE_COPY_SEND,
      MACH_MSG_TYPE_MAKE_SEND,
      0,
      MACH_MSGH_BITS_COMPLEX);
    message.header.msgh_size = sizeof(message);
    message.descriptorCount = 1;
    message.descriptor.address = (void *)payload.bytes;
    message.descriptor.size = (mach_msg_size_t)payload.length;
    message.descriptor.copy = MACH_MSG_VIRTUAL_COPY;
    message.descriptor.deallocate = false;
    message.descriptor.type = MACH_MSG_OOL_DESCRIPTOR;

    mach_msg_return_t result = mach_msg(&message.header,
                                        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                        sizeof(message),
                                        0,
                                        MACH_PORT_NULL,
                                        kMachSendTimeoutMilliseconds,
                                        MACH_PORT_NULL);
    mach_port_deallocate(task, port);

    BOOL success = NO;
    if (result == MACH_MSG_SUCCESS) {
      struct barista_mach_buffer buffer = {0};
      result = mach_msg(&buffer.message.header,
                        MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                        0,
                        sizeof(buffer),
                        responsePort,
                        kMachReceiveTimeoutMilliseconds,
                        MACH_PORT_NULL);
      if (result == MACH_MSG_SUCCESS) {
        mach_msg_ool_descriptor_t descriptor = buffer.message.descriptor;
        if (buffer.message.descriptorCount == 1
            && descriptor.type == MACH_MSG_OOL_DESCRIPTOR
            && descriptor.address != NULL
            && descriptor.size > 0
            && descriptor.size <= kMaxPayloadBytes) {
          success = response_is_success(descriptor.address, descriptor.size);
        }
        mach_msg_destroy(&buffer.message.header);
      }
    }
    mach_port_mod_refs(task, responsePort, MACH_PORT_RIGHT_RECEIVE, -1);
    mach_port_deallocate(task, responsePort);
    if (success) return YES;
  }
  return NO;
}

static BOOL native_disabled(void) {
  BOOL disabled = NO;
  return parse_bool_strict(environment_value(@"BARISTA_VOLUME_NATIVE_DISABLE"), &disabled)
    && disabled;
}

static void usage(const char *program) {
  fprintf(stderr, "Usage: %s [popup_refresh] [--dump0]\n", program);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    BOOL dumpPayload = NO;
    for (int index = 1; index < argc; index++) {
      if (strcmp(argv[index], "popup_refresh") == 0) {
        continue;
      }
      if (strcmp(argv[index], "--dump0") == 0) {
        dumpPayload = YES;
        continue;
      }
      usage(argv[0]);
      return 2;
    }
    if (native_disabled()) {
      return 3;
    }

    NSArray<NSString *> *tokens = build_tokens();
    NSData *payload = tokens ? payload_for_tokens(tokens) : nil;
    if (!payload) {
      return 3;
    }
    if (dumpPayload) {
      return fwrite(payload.bytes, 1, payload.length, stdout) == payload.length ? 0 : 4;
    }

    if (!send_payload(payload)) {
      return 4;
    }
    return 0;
  }
}
