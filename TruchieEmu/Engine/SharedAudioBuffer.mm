#import "SharedAudioBuffer.h"

// Define the layout of the shared memory region
typedef struct {
    atomic_size_t head;
    atomic_size_t tail;
    size_t capacity;
    int16_t data[]; // Flexible array member
} SharedBufferHeader;

@implementation SharedAudioBuffer {
    int _fd;
    size_t _mappedSize;
    SharedBufferHeader *_header;
    NSString *_name;
}

- (instancetype)initAsHostWithName:(NSString *)name capacity:(size_t)capacity {
    if (self = [super init]) {
        _name = [name copy];
        _mappedSize = sizeof(SharedBufferHeader) + (capacity * sizeof(int16_t));
        
        // Remove existing if unlinked improperly
        shm_unlink(_name.UTF8String);
        
        _fd = shm_open(_name.UTF8String, O_CREAT | O_RDWR, 0666);
        if (_fd < 0) return nil;
        
        if (ftruncate(_fd, _mappedSize) != 0) {
            close(_fd);
            return nil;
        }
        
        _header = (SharedBufferHeader *)mmap(NULL, _mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, _fd, 0);
        if (_header == MAP_FAILED) {
            close(_fd);
            return nil;
        }
        
        atomic_init(&_header->head, 0);
        atomic_init(&_header->tail, 0);
        _header->capacity = capacity;
    }
    return self;
}

- (instancetype)initAsGuestWithName:(NSString *)name {
    if (self = [super init]) {
        _name = [name copy];
        
        _fd = shm_open(_name.UTF8String, O_RDWR, 0666);
        if (_fd < 0) return nil;
        
        struct stat st;
        if (fstat(_fd, &st) != 0) {
            close(_fd);
            return nil;
        }
        
        _mappedSize = st.st_size;
        _header = (SharedBufferHeader *)mmap(NULL, _mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, _fd, 0);
        if (_header == MAP_FAILED) {
            close(_fd);
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_header && _header != MAP_FAILED) {
        munmap(_header, _mappedSize);
    }
    if (_fd >= 0) {
        close(_fd);
    }
    // Only host should unlink realistically, but doing it here is safe if refcounts drop
}

- (size_t)writeSamples:(const int16_t *)samples count:(size_t)count {
    if (!_header) return 0;
    
    size_t head = atomic_load_explicit(&_header->head, memory_order_acquire);
    size_t tail = atomic_load_explicit(&_header->tail, memory_order_relaxed);
    size_t capacity = _header->capacity;
    
    size_t available = (head + capacity - tail - 1) % capacity;
    size_t toWrite = (count < available) ? count : available;
    
    if (toWrite == 0) return 0; // Buffer full
    
    // Write in two chunks if wrapping around
    size_t firstChunk = capacity - tail;
    if (firstChunk > toWrite) firstChunk = toWrite;
    
    memcpy(&_header->data[tail], samples, firstChunk * sizeof(int16_t));
    
    if (toWrite > firstChunk) {
        memcpy(&_header->data[0], samples + firstChunk, (toWrite - firstChunk) * sizeof(int16_t));
    }
    
    atomic_store_explicit(&_header->tail, (tail + toWrite) % capacity, memory_order_release);
    return toWrite;
}

- (size_t)readSamples:(int16_t *)buffer count:(size_t)count {
    if (!_header) return 0;
    
    size_t tail = atomic_load_explicit(&_header->tail, memory_order_acquire);
    size_t head = atomic_load_explicit(&_header->head, memory_order_relaxed);
    size_t capacity = _header->capacity;
    
    size_t available = (tail + capacity - head) % capacity;
    size_t toRead = (count < available) ? count : available;
    
    if (toRead == 0) return 0; // Buffer empty
    
    size_t firstChunk = capacity - head;
    if (firstChunk > toRead) firstChunk = toRead;
    
    memcpy(buffer, &_header->data[head], firstChunk * sizeof(int16_t));
    
    if (toRead > firstChunk) {
        memcpy(buffer + firstChunk, &_header->data[0], (toRead - firstChunk) * sizeof(int16_t));
    }
    
    atomic_store_explicit(&_header->head, (head + toRead) % capacity, memory_order_release);
    return toRead;
}

- (size_t)availableRead {
    if (!_header) return 0;
    size_t tail = atomic_load_explicit(&_header->tail, memory_order_acquire);
    size_t head = atomic_load_explicit(&_header->head, memory_order_relaxed);
    return (tail + _header->capacity - head) % _header->capacity;
}

- (size_t)availableWrite {
    if (!_header) return 0;
    size_t head = atomic_load_explicit(&_header->head, memory_order_acquire);
    size_t tail = atomic_load_explicit(&_header->tail, memory_order_relaxed);
    return (head + _header->capacity - tail - 1) % _header->capacity;
}

@end
