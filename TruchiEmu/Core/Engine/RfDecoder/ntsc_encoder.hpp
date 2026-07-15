#pragma once

#include <cstdint>
#include <complex>
#include <random>
#include <vector>

namespace famidec {

// "Digital -> RF" stage. Takes a decoded game frame (RGBA8) and synthesizes
// the NTSC-J composite baseband (with sync, color burst, active video) then
// modulates it onto a VHF carrier as complex IQ @ sample_rate — the exact
// signal a HackRF would capture from a Famicom RF modulator. The downstream
// front-end (DcBlocker -> NCO mixer -> 4.3 MHz LPF -> EnvelopeDetector) and
// NtscDecoder turn it back into a 640x480 RGB frame, reproducing authentic
// RF/NTSC artifacts.
//
// RF realism knobs (mirroring the upstream --freq / snow / ghosting controls):
//   signal_strength : 1.0 = full lock, lower -> more snow (additive noise)
//   snow_amount     : noise-floor scale (0..1)
//   tuning_hz       : carrier offset deviation -> herringbone when off-tune
//   ghosting        : RF multipath: a dim, time-delayed spatial echo (0..1)
struct RfEncoderParams {
    double sample_rate = 10e6;
    double offset_hz = 2.0e6;        // center = carrier + offset (avoid DC spike)
    int lines_per_field = 262;       // 240p non-interlaced field length
    int vsync_lines = 3;
    int active_start_line = 13;      // matches NtscDecoder::kActiveStartLine
    int active_lines = 240;          // matches NtscDecoder::kActiveLines

    float signal_strength = 1.0f;    // 0..1
    float snow_amount = 0.0f;        // 0..1
    float tuning_hz = 0.0f;          // carrier offset deviation
    float ghosting = 0.0f;           // 0..1 multipath echo
};

class NtscRfEncoder {
public:
    explicit NtscRfEncoder(const RfEncoderParams& p);

    // Encode one field from `rgba` (srcW x srcH, RGBA8, row-major) into `out`
    // as complex<float> IQ. Source rows are scaled into the 240 active lines;
    // source columns are scaled into the 52.6 us active window. State
    // (subcarrier phase, multipath history, noise generator) persists across
    // calls so back-to-back fields stay phase-continuous and decoder-locked.
    void encode_field(const uint8_t* rgba, int srcW, int srcH,
                      std::vector<std::complex<float>>& out);

    // Same, but writes interleaved int8 IQ (for .cs8 capture / debugging).
    void encode_field_int8(const uint8_t* rgba, int srcW, int srcH,
                           std::vector<uint8_t>& out);

    int samples_per_line() const { return samples_per_line_; }
    size_t field_samples() const {
        return static_cast<size_t>(samples_per_line_) * params_.lines_per_field;
    }

    // Read-only access to the current (base) RF knobs so a caller can layer
    // dynamic instability on top without the values accumulating frame-over-frame.
    const RfEncoderParams& params() const { return params_; }

    // Live RF-knob updates (no realloc beyond the multipath echo history).
    void set_rf_knobs(float signal_strength, float snow_amount,
                      float tuning_hz, float ghosting) {
        params_.signal_strength = signal_strength;
        params_.snow_amount = snow_amount;
        params_.tuning_hz = tuning_hz;
        params_.ghosting = ghosting;
        omega_c_ = -2.0 * M_PI * params_.offset_hz / params_.sample_rate
                   - 2.0 * M_PI * tuning_hz / params_.sample_rate;
        // Per-frame tuning rotation applied to the precomputed base carrier.
        double tune_arg = 2.0 * M_PI * tuning_hz / params_.sample_rate;
        tune_step_ = std::complex<float>(static_cast<float>(std::cos(tune_arg)),
                                         static_cast<float>(std::sin(tune_arg)));
        echo_delay_ = static_cast<int>(0.00015 * params_.sample_rate);
        echo_hist_.assign(static_cast<size_t>(echo_delay_),
                          std::complex<float>(0, 0));
        echo_pos_ = 0;
    }

    void reset_state() {
        echo_hist_.assign(static_cast<size_t>(echo_delay_),
                          std::complex<float>(0, 0));
        echo_pos_ = 0;
    }

private:
    // Precomputed per-sample tables (built once per field geometry) so the
    // hot encode loop does zero trig / fmod / branching:
    //   car*_ : base (un-tuned) carrier sin/cos, one per field sample
    //   sub*_ : color-subcarrier sin/cos, one per field sample
    //   srcIdx_: source RGBA byte offset for active-video samples, -1 else
    //   ireConst_: IRE for non-active samples (sync / burst / porch)
    void build_carrier_table();
    void build_geometry(int srcW, int srcH);
    void prepare(int srcW, int srcH) {
        if (!table_ready_ || tbl_w_ != srcW || tbl_h_ != srcH)
            build_geometry(srcW, srcH);
    }

    RfEncoderParams params_;
    double omega_sc_;
    double omega_c_;
    double omega_c_base_;
    int samples_per_line_;

    std::vector<float> car_cos_, car_sin_;
    std::vector<float> sub_sin_, sub_cos_;
    std::vector<int> src_idx_;
    std::vector<float> ire_const_;
    bool table_ready_ = false;
    int tbl_w_ = 0, tbl_h_ = 0;
    std::complex<float> tune_step_{1.0f, 0.0f};

    // Multipath echo history (complex IQ ring buffer).
    std::vector<std::complex<float>> echo_hist_;
    int echo_delay_ = 150;
    size_t echo_pos_ = 0;

    std::mt19937 rng_;
    std::normal_distribution<float> gauss_;
};

}  // namespace famidec
