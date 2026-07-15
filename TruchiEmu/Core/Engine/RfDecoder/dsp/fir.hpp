#pragma once

#include <cmath>
#include <complex>
#include <cstddef>
#include <vector>

namespace famidec {

// Windowed-sinc FIR design (Hamming window).
inline std::vector<float> design_lowpass(double cutoff_hz, double sample_rate,
                                         int taps) {
    // taps must be odd for a symmetric type-I filter
    if ((taps & 1) == 0) ++taps;
    std::vector<float> h(taps);
    double fc = cutoff_hz / sample_rate;  // normalized (0..0.5)
    int m = taps - 1;
    double sum = 0.0;
    for (int i = 0; i < taps; ++i) {
        double n = i - m / 2.0;
        double sinc = (n == 0.0) ? 2.0 * fc
                                 : std::sin(2.0 * M_PI * fc * n) / (M_PI * n);
        double w = 0.54 - 0.46 * std::cos(2.0 * M_PI * i / m);
        h[i] = static_cast<float>(sinc * w);
        sum += h[i];
    }
    for (auto& v : h) v = static_cast<float>(v / sum);  // unity DC gain
    return h;
}

inline std::vector<float> design_bandpass(double f_lo, double f_hi,
                                          double sample_rate, int taps) {
    if ((taps & 1) == 0) ++taps;
    double fc = 0.5 * (f_lo + f_hi);
    double half_bw = 0.5 * (f_hi - f_lo);
    auto lp = design_lowpass(half_bw, sample_rate, taps);
    // Modulate lowpass prototype up to center frequency; x2 to keep passband
    // gain at unity for a real bandpass.
    std::vector<float> h(lp.size());
    int m = static_cast<int>(lp.size()) - 1;
    for (size_t i = 0; i < lp.size(); ++i) {
        double n = static_cast<double>(i) - m / 2.0;
        h[i] = static_cast<float>(
            2.0 * lp[i] * std::cos(2.0 * M_PI * fc / sample_rate * n));
    }
    return h;
}

// Streaming FIR over a contiguous block, with history carried across calls.
template <typename Sample>
class FirFilter {
public:
    explicit FirFilter(std::vector<float> taps)
        : taps_(std::move(taps)), hist_(taps_.size() - 1, Sample{}) {}

    size_t delay() const { return (taps_.size() - 1) / 2; }

    // in/out may be the same buffer.
    void process(const Sample* in, Sample* out, size_t n) {
        size_t nt = taps_.size();
        size_t nh = nt - 1;
        // Work buffer: history + new samples
        work_.resize(nh + n);
        std::copy(hist_.begin(), hist_.end(), work_.begin());
        std::copy(in, in + n, work_.begin() + nh);
        for (size_t i = 0; i < n; ++i) {
            Sample acc{};
            const Sample* w = work_.data() + i;
            for (size_t k = 0; k < nt; ++k) acc += w[k] * taps_[nt - 1 - k];
            out[i] = acc;
        }
        std::copy(work_.end() - nh, work_.end(), hist_.begin());
    }

private:
    std::vector<float> taps_;
    std::vector<Sample> hist_;
    std::vector<Sample> work_;
};

using FirFilterF = FirFilter<float>;
using FirFilterC = FirFilter<std::complex<float>>;

}  // namespace famidec
