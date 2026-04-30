#pragma once

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <stdint.h>

class AudioRingBuffer {
public:
  AudioRingBuffer(size_t capacity) : _capacity(capacity) {
    _buffer = (int16_t *)malloc(capacity * sizeof(int16_t));
    _readPtr = 0;
    _writePtr = 0;
    _fillCount = 0;
  }
  ~AudioRingBuffer() { free(_buffer); }

  size_t write(const int16_t *data, size_t count) {
    size_t written = 0;
    for (size_t i = 0; i < count; ++i) {
      if (_fillCount < _capacity) {
        _buffer[_writePtr] = data[i];
        _writePtr = (_writePtr + 1) % _capacity;
        _fillCount++;
        written++;
      } else {
        break; // Overflow
      }
    }
    return written;
  }

  size_t read(int16_t *data, size_t count) {
    size_t r = 0;
    for (size_t i = 0; i < count; ++i) {
      if (_fillCount > 0) {
        data[i] = _buffer[_readPtr];
        _readPtr = (_readPtr + 1) % _capacity;
        _fillCount--;
        r++;
      } else {
        break; // Underflow
      }
    }
    return r;
  }

  void clear() {
    _readPtr = 0;
    _writePtr = 0;
    _fillCount = 0;
  }

  size_t available() const { return _fillCount; }
  size_t capacity() const { return _capacity; }

private:
  int16_t *_buffer;
  size_t _capacity;
  size_t _readPtr;
  size_t _writePtr;
  std::atomic<size_t> _fillCount;
};