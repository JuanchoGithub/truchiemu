#pragma once

#include <cmath>
#include <complex>
#include <cstddef>

namespace famidec {

// Measures the color burst phase/amplitude over a gated segment.
// theta(j) is the free-running subcarrier angle at each sample. The burst is
// transmitted as -sin(theta_tx); correlating against exp(-j*theta) yields
// arg(B) = phi_b + 90deg, where phi_b is the transmitter phase offset such
// that sin_tx(t) = sin(theta(t) + phi_b).
struct BurstMeasurement {
    double phase = 0.0;  // phi_b
    float amplitude = 0.0f;
    bool valid = false;
};

inline BurstMeasurement measure_burst(const float* chroma, size_t n,
                                      double theta0, double dtheta,
                                      float min_amplitude) {
    std::complex<double> acc(0.0, 0.0);
    double th = theta0;
    for (size_t j = 0; j < n; ++j) {
        acc += std::complex<double>(chroma[j] * std::cos(th),
                                    -chroma[j] * std::sin(th));
        th += dtheta;
    }
    BurstMeasurement m;
    m.amplitude = static_cast<float>(std::abs(acc) / n);
    m.phase = std::arg(acc) - M_PI / 2.0;
    m.valid = m.amplitude >= min_amplitude;
    return m;
}

}  // namespace famidec
