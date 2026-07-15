#pragma once

#include <algorithm>
#include <cmath>
#include <vector>

namespace famidec {

// Tracks sync-tip and blanking levels of the raw (detected, positive-going
// sync because of negative modulation) composite and converts to IRE:
// sync tip = -40 IRE, blanking = 0 IRE, white ~ +100 IRE.
class Agc {
public:
    // Bootstrap from level percentiles over an observation window (several
    // dozen lines); refined per line afterwards. Absolute extrema are not
    // usable on real signals — noise spikes inflate the peak and push the
    // sync slicer above the actual sync tips.
    static constexpr int kBootstrapSamples = 50000;  // 5 ms at 10 MSPS

    void bootstrap(float raw) {
        if ((boot_count_ & 15) == 0) reservoir_.push_back(raw);
        if (++boot_count_ < kBootstrapSamples) return;
        // Sync tips occupy the top few percent of samples in time.
        auto pct = [this](float p) {
            size_t k = static_cast<size_t>(p * (reservoir_.size() - 1));
            std::nth_element(reservoir_.begin(), reservoir_.begin() + k,
                             reservoir_.end());
            return reservoir_[k];
        };
        float lo = pct(0.02f);
        float hi = pct(0.98f);
        if (hi > lo + 1e-4f) {
            tip_ = hi;
            // Full modulation range tip..white spans 140 IRE.
            blank_ = hi - (hi - lo) * (40.0f / 140.0f);
            seeded_ = true;
            reservoir_.clear();
            reservoir_.shrink_to_fit();
        } else {
            boot_count_ = 0;  // flat input, keep observing
            reservoir_.clear();
        }
    }

    bool seeded() const { return seeded_; }

    // Per-line refinement with measured sync tip and back-porch average.
    void update(float tip_meas, float blank_meas) {
        if (tip_meas <= blank_meas) return;  // implausible, skip
        tip_ = tip_ + 0.05f * (tip_meas - tip_);
        blank_ = blank_ + 0.05f * (blank_meas - blank_);
        seeded_ = true;
    }

    // Per-line refinement from measurements taken in the IRE domain (i.e.
    // after conversion with the current mapping): invert the mapping to get
    // the implied raw levels, then track them.
    void update_from_ire(float tip_ire, float blank_ire) {
        update(from_ire(tip_ire), from_ire(blank_ire));
    }

    float from_ire(float ire) const {
        float span = tip_ - blank_;
        return blank_ - ire * span / 40.0f;
    }

    float to_ire(float raw) const {
        float span = tip_ - blank_;  // 40 IRE worth of raw amplitude
        if (span < 1e-6f) return 0.0f;
        return (blank_ - raw) * (40.0f / span);
    }

    // Gain for band-pass filtered raw (the blank offset is DC-rejected by
    // the filter). Negative: IRE is inverted relative to raw.
    float chroma_scale() const {
        float span = tip_ - blank_;
        if (span < 1e-6f) return 0.0f;
        return -40.0f / span;
    }

    float tip() const { return tip_; }
    float blank() const { return blank_; }

private:
    float tip_ = 1.0f;
    float blank_ = 0.7f;
    std::vector<float> reservoir_;
    int boot_count_ = 0;
    bool seeded_ = false;
};

}  // namespace famidec
