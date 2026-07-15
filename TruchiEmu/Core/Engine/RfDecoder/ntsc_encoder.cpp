#include "ntsc_encoder.hpp"

#include <cmath>

namespace famidec {

namespace {
constexpr double kLineRate = 15734.264;            // Hz
constexpr double kLineUs = 1e6 / kLineRate;        // 63.555 us
constexpr double kFsc = 315e6 / 88.0;              // 3.579545 MHz
constexpr double kActiveStartUs = 9.4;
constexpr double kActiveSpanUs = 52.6;             // active window width
constexpr double kSyncUs = 4.7;
constexpr double kBurstStartUs = 5.3;
constexpr double kBurstEndUs = 7.8;

inline void rgb_to_yiq(uint8_t r8, uint8_t g8, uint8_t b8,
                       float* y, float* u, float* v) {
    float r = r8 / 255.0f, g = g8 / 255.0f, b = b8 / 255.0f;
    *y = 0.299f * r + 0.587f * g + 0.114f * b;
    *u = 0.492f * (b - *y);
    *v = 0.877f * (r - *y);
}
}  // namespace

NtscRfEncoder::NtscRfEncoder(const RfEncoderParams& p)
    : params_(p),
      omega_sc_(2.0 * M_PI * kFsc / p.sample_rate),
      omega_c_(-2.0 * M_PI * p.offset_hz / p.sample_rate),
      omega_c_base_(-2.0 * M_PI * p.offset_hz / p.sample_rate),
      samples_per_line_(static_cast<int>(std::lround(p.sample_rate / kLineRate))),
      rng_(0x9e3779b9u),
      gauss_(0.0f, 1.0f) {
    omega_c_ -= 2.0 * M_PI * p.tuning_hz / p.sample_rate;
    echo_delay_ = static_cast<int>(0.00015 * p.sample_rate);  // ~150 us echo
    echo_hist_.assign(static_cast<size_t>(echo_delay_), std::complex<float>(0, 0));
    build_carrier_table();
}

void NtscRfEncoder::build_carrier_table() {
    const size_t N = field_samples();
    car_cos_.resize(N);
    car_sin_.resize(N);
    double ph = 0.0;
    const double inc = omega_c_base_;
    for (size_t s = 0; s < N; ++s) {
        car_cos_[s] = static_cast<float>(std::cos(ph));
        car_sin_[s] = static_cast<float>(std::sin(ph));
        ph += inc;
        if (ph > M_PI) ph -= 2.0 * M_PI;
        else if (ph < -M_PI) ph += 2.0 * M_PI;
    }
}

void NtscRfEncoder::build_geometry(int w, int h) {
    const size_t N = field_samples();
    sub_sin_.resize(N);
    sub_cos_.resize(N);
    src_idx_.assign(N, -1);
    ire_const_.assign(N, 0.0f);

    // Subcarrier tables (per field sample, phase wraps to stay in range).
    double sub = 0.0;
    for (size_t s = 0; s < N; ++s) {
        sub_sin_[s] = static_cast<float>(std::sin(sub));
        sub_cos_[s] = static_cast<float>(std::cos(sub));
        sub += omega_sc_;
        if (sub > 2.0 * M_PI) sub -= 2.0 * M_PI;
    }

    // Per-sample geometry: classify each field sample into sync / burst /
    // porch / active and, for active, which source pixel it samples.
    for (size_t s = 0; s < N; ++s) {
        int line = static_cast<int>(s / static_cast<size_t>(samples_per_line_));
        int s_in_line = static_cast<int>(s % static_cast<size_t>(samples_per_line_));
        double us = static_cast<double>(s_in_line) / params_.sample_rate * 1e6;

        if (line < params_.vsync_lines) {
            ire_const_[s] = (us > kLineUs - kSyncUs) ? 0.0f : -40.0f;
            continue;
        }
        if (us < kSyncUs) { ire_const_[s] = -40.0f; continue; }
        if (us >= kBurstStartUs && us < kBurstEndUs) {
            ire_const_[s] = -20.0f * sub_sin_[s];
            continue;
        }
        if (us < kActiveStartUs || us >= kActiveStartUs + kActiveSpanUs) {
            ire_const_[s] = 0.0f;
            continue;
        }
        int al = line - params_.active_start_line;
        if (al < 0 || al >= params_.active_lines) continue;
        if (al >= h) continue;

        double frac = (us - kActiveStartUs) / kActiveSpanUs;
        int sx = static_cast<int>(frac * w);
        if (sx < 0) sx = 0;
        if (sx >= w) sx = w - 1;
        int sy = static_cast<int>(static_cast<double>(al) * h /
                                  static_cast<double>(params_.active_lines));
        if (sy < 0) sy = 0;
        if (sy >= h) sy = h - 1;
        src_idx_[s] = (sy * w + sx) * 4;
    }
    tbl_w_ = w;
    tbl_h_ = h;
    table_ready_ = true;
}

void NtscRfEncoder::encode_field(const uint8_t* rgba, int srcW, int srcH,
                                 std::vector<std::complex<float>>& out) {
    prepare(srcW, srcH);
    const size_t N = field_samples();
    out.resize(N);

    // Noise floor dominates as the carrier fades. When signal_strength -> 0
    // the carrier vanishes and the envelope is pure noise, so the downstream
    // decoder loses sync and free-runs (genuine grey "snow"), and a weak
    // carrier drops the color burst below threshold -> automatic B&W.
    float noise_amp = (1.0f - params_.signal_strength) * 0.45f +
                      params_.snow_amount * 0.15f;
    float ghost_gain = params_.ghosting * 0.5f;

    std::complex<float> cur(1.0f, 0.0f);  // per-field tuning rotation
    const std::complex<float> step = tune_step_;

    for (size_t s = 0; s < N; ++s) {
        float ire;
        int idx = src_idx_[s];
        if (idx >= 0) {
            const uint8_t* px = rgba + static_cast<size_t>(idx);
            float y, u, v;
            rgb_to_yiq(px[0], px[1], px[2], &y, &u, &v);
            float chroma = u * sub_sin_[s] + v * sub_cos_[s];
            ire = (y + chroma) * 100.0f;
        } else {
            ire = ire_const_[s];
        }

        // Negative modulation: sync tip (IRE -40) = 100% carrier,
        // white (IRE +100) = 12.5% carrier.
        float amp = (0.75f - ire * (0.625f / 100.0f)) * params_.signal_strength;

        // carrier = baseCarrier[s] * tuningRotation (no trig in loop)
        float re = car_cos_[s] * cur.real() - car_sin_[s] * cur.imag();
        float im = car_sin_[s] * cur.real() + car_cos_[s] * cur.imag();
        std::complex<float> c(amp * re, amp * im);

        if (noise_amp > 0.0f) {
            c += std::complex<float>(gauss_(rng_) * noise_amp,
                                     gauss_(rng_) * noise_amp);
        }
        if (ghost_gain > 0.0f) {
            c += ghost_gain * echo_hist_[echo_pos_];
        }

        echo_hist_[echo_pos_] = c;
        echo_pos_ = (echo_pos_ + 1) % echo_hist_.size();
        out[s] = c;
        cur *= step;
    }
}

void NtscRfEncoder::encode_field_int8(const uint8_t* rgba, int srcW, int srcH,
                                     std::vector<uint8_t>& out) {
    std::vector<std::complex<float>> tmp;
    encode_field(rgba, srcW, srcH, tmp);
    out.resize(tmp.size() * 2);
    auto clip8 = [](float x) {
        return static_cast<uint8_t>(static_cast<int8_t>(std::lround(
            std::fmax(-127.0f, std::fmin(127.0f, x)))));
    };
    for (size_t i = 0; i < tmp.size(); ++i) {
        out[2 * i] = clip8(100.0f * tmp[i].real());
        out[2 * i + 1] = clip8(100.0f * tmp[i].imag());
    }
}

}  // namespace famidec
