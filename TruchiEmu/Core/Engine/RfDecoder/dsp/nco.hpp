#pragma once

#include <cmath>
#include <complex>

namespace famidec {

// Numerically controlled oscillator. Phase accumulated in double to keep
// long-term frequency accuracy; output produced as float complex.
class Nco {
public:
    Nco(double freq_hz, double sample_rate)
        : phase_inc_(2.0 * M_PI * freq_hz / sample_rate) {}

    void set_freq(double freq_hz, double sample_rate) {
        phase_inc_ = 2.0 * M_PI * freq_hz / sample_rate;
    }

    double phase() const { return phase_; }
    double phase_inc() const { return phase_inc_; }
    void adjust_phase(double d) { phase_ = wrap(phase_ + d); }
    void adjust_freq(double d) { phase_inc_ += d; }

    std::complex<float> next() {
        std::complex<float> out(std::cos(static_cast<float>(phase_)),
                                std::sin(static_cast<float>(phase_)));
        phase_ = wrap(phase_ + phase_inc_);
        return out;
    }

    static double wrap(double p) {
        if (p > M_PI) p -= 2.0 * M_PI;
        else if (p < -M_PI) p += 2.0 * M_PI;
        return p;
    }

private:
    double phase_ = 0.0;
    double phase_inc_;
};

}  // namespace famidec
