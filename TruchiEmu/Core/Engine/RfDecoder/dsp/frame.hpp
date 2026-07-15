#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

namespace famidec {

struct Frame {
    static constexpr int kWidth = 640;
    static constexpr int kHeight = 480;
    std::vector<uint32_t> rgba;  // ABGR8888 byte order R,G,B,A in memory
    uint64_t seq = 0;

    Frame() : rgba(kWidth * kHeight, 0xff000000u) {}
};

// Triple buffer: DSP thread writes into back(), publishes; render thread
// acquires the freshest published frame. Lock-free via atomic index packing.
class TripleBuffer {
public:
    Frame& back() { return bufs_[back_idx_]; }

    void publish(uint64_t seq) {
        bufs_[back_idx_].seq = seq;
        // swap back with "middle" slot; mark fresh bit
        int mid = middle_.exchange(back_idx_ | kFresh, std::memory_order_acq_rel);
        back_idx_ = mid & kIdxMask;
    }

    // Returns nullptr if no new frame since last acquire.
    const Frame* acquire() {
        int mid = middle_.load(std::memory_order_acquire);
        if (!(mid & kFresh)) return nullptr;
        mid = middle_.exchange(front_idx_, std::memory_order_acq_rel);
        if (!(mid & kFresh)) return nullptr;  // raced with publish; rare
        front_idx_ = mid & kIdxMask;
        return &bufs_[front_idx_];
    }

private:
    static constexpr int kFresh = 4;
    static constexpr int kIdxMask = 3;
    Frame bufs_[3];
    int back_idx_ = 0;
    int front_idx_ = 2;
    std::atomic<int> middle_{1};
};

}  // namespace famidec
