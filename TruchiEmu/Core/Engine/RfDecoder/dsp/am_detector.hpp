#pragma once

#include <cmath>
#include <complex>
#include <cstddef>

#include "nco.hpp"

namespace famidec {

// Envelope detector: composite = |x|. Simple and robust; quadrature
// distortion from VSB is acceptable since chroma locks to the burst.
class EnvelopeDetector {
public:
    void process(const std::complex<float>* in, float* out, size_t n) {
        for (size_t i = 0; i < n; ++i) out[i] = std::abs(in[i]);
    }
};

// Synchronous detector: 2nd-order carrier-tracking PLL, composite is the
// in-phase component. Cleaner than envelope for weak signals / chroma.
class SyncDetector {
public:
    SyncDetector(double sample_rate, double loop_bw_hz = 500.0)
        : nco_(0.0, sample_rate) {
        double wn = 2.0 * M_PI * loop_bw_hz / sample_rate;
        double zeta = 0.7071;
        kp_ = 2.0 * zeta * wn;
        ki_ = wn * wn;
    }

    void process(const std::complex<float>* in, float* out, size_t n) {
        for (size_t i = 0; i < n; ++i) {
            std::complex<float> vco = nco_.next();
            std::complex<float> bb = in[i] * std::conj(vco);
            float mag = std::abs(bb);
            out[i] = bb.real();
            if (mag > 1e-6f) {
                double err = bb.imag() / mag;
                freq_int_ += ki_ * err;
                nco_.adjust_phase(kp_ * err + freq_int_);
            }
        }
    }

private:
    Nco nco_;
    double kp_, ki_;
    double freq_int_ = 0.0;
};

}  // namespace famidec
