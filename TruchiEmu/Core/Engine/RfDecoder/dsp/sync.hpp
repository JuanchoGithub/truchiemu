#pragma once

#include <cmath>
#include <cstdint>

namespace famidec {

// Flywheel PLL on the horizontal line period. Positions are absolute sample
// indices (double, fractional).
struct LinePll {
    double period = 0.0;       // samples per line
    double nominal = 0.0;
    double next_edge = 0.0;    // predicted absolute position of next hsync
    bool locked = false;
    int coast = 0;             // consecutive lines without a usable edge
    int good = 0;              // consecutive good edges (for lock acquisition)

    static constexpr double kPullRange = 0.005;  // +-0.5% of nominal
    static constexpr int kCoastLimit = 45;
    static constexpr int kLockThreshold = 8;

    void init(double nominal_period) {
        nominal = nominal_period;
        period = nominal_period;
    }

    // Called once per line with the measured edge position (has_meas=false
    // when no usable edge was found). Returns the edge position to use.
    double advance(bool has_meas, double measured) {
        double used;
        if (has_meas) {
            double err = measured - next_edge;
            // proportional on phase, integral on period
            used = next_edge + 0.3 * err;
            period += 0.02 * err;
            double lo = nominal * (1.0 - kPullRange);
            double hi = nominal * (1.0 + kPullRange);
            if (period < lo) period = lo;
            if (period > hi) period = hi;
            coast = 0;
            if (++good >= kLockThreshold) locked = true;
        } else {
            used = next_edge;
            good = 0;
            if (++coast > kCoastLimit) locked = false;
        }
        next_edge = used + period;
        return used;
    }

    void acquire(double edge_pos, double measured_period) {
        period = measured_period;
        next_edge = edge_pos + period;
        coast = 0;
    }
};

}  // namespace famidec
