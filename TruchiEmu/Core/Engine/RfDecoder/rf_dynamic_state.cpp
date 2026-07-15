#include "rf_dynamic_state.h"

#include <atomic>

namespace {
// Relaxed atomics are enough: the writer (emulation thread) publishes a full
// struct each frame and the reader (render thread) consumes a snapshot.
std::atomic<RfDynamicState> g_state{};
}  // namespace

void RfDynamicStateSet(const RfDynamicState* s) {
    g_state.store(*s, std::memory_order_relaxed);
}

RfDynamicState RfDynamicStateGet(void) {
    return g_state.load(std::memory_order_relaxed);
}
