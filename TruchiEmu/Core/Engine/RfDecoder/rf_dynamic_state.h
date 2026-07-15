#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Per-frame dynamic instability state produced by the RF decoder bridge
// (dropouts, vertical-hold loss / diagonal roll, random "bump" glitches) and
// consumed by the RfDisplay Metal pass. Kept as a plain C store so the
// emulation-thread writer and the render-thread reader never touch Swift/ObjC.
typedef struct RfDynamicState {
    float signalLoss;   // 0..1 grey static / carrier-loss mix
    float rollOffset;   // 0..1 vertical scroll (wraps)
    float rollShear;    // 0..1 horizontal shear per vertical unit (diagonal)
    float glitch;       // 0..1 bump glitch intensity
    float tear;         // 0..1 horizontal tear bands
    float hShift;       // -1..1 random horizontal jump
    uint64_t frame;
} RfDynamicState;

void RfDynamicStateSet(const RfDynamicState* s);
RfDynamicState RfDynamicStateGet(void);

#ifdef __cplusplus
}
#endif
