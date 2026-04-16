#import <Foundation/Foundation.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <stdatomic.h>

/**
 * SharedAudioBuffer implements a lock-free circular buffer over POSIX shared memory.
 * It is used to pass audio samples from TruchiCoreRunner to the Host.
 */
@interface SharedAudioBuffer : NSObject

/// Host side: Create the shared memory buffer with a unique name.
- (instancetype)initAsHostWithName:(NSString *)name capacity:(size_t)capacity;

/// Guest side: Open an existing shared memory buffer.
- (instancetype)initAsGuestWithName:(NSString *)name;

/// Write samples (Guest)
- (size_t)writeSamples:(const int16_t *)samples count:(size_t)count;

/// Read samples (Host)
- (size_t)readSamples:(int16_t *)buffer count:(size_t)count;

/// Available samples for reading
- (size_t)availableRead;

/// Available space for writing
- (size_t)availableWrite;

@end
