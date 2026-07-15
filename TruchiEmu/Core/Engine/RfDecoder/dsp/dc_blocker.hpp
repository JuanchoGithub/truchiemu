#pragma once

#include <complex>

namespace famidec {

// One-pole complex DC blocker: y[n] = x[n] - x[n-1] + r*y[n-1]
class DcBlocker {
public:
    explicit DcBlocker(float r = 0.9995f) : r_(r) {}

    std::complex<float> process(std::complex<float> x) {
        std::complex<float> y = x - prev_x_ + r_ * prev_y_;
        prev_x_ = x;
        prev_y_ = y;
        return y;
    }

private:
    float r_;
    std::complex<float> prev_x_{0.0f, 0.0f};
    std::complex<float> prev_y_{0.0f, 0.0f};
};

}  // namespace famidec
