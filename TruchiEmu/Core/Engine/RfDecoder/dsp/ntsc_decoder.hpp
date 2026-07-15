#pragma once

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "../config.hpp"
#include "agc.hpp"
#include "fir.hpp"
#include "frame.hpp"
#include "sync.hpp"

namespace famidec {

// Composite (detected envelope, raw units, positive-going sync) -> RGB frames.
class NtscDecoder {
public:
    static constexpr double kFsc = 315e6 / 88.0;      // 3.579545... MHz
    static constexpr double kLineRate = 15734.264;    // Hz (NTSC nominal)
    static constexpr int kActiveLines = 240;
    static constexpr int kActiveStartLine = 13;       // lines after vsync end

    struct Stats {
        std::atomic<bool> line_locked{false};
        std::atomic<float> burst_amp{0.0f};
        std::atomic<uint64_t> frames{0};
        std::atomic<uint64_t> lines{0};
        std::atomic<uint64_t> lines_coasted{0};
        std::atomic<float> line_period{0.0f};
        // Absolute input-sample index of the most recently published
        // frame's vsync, and total samples fed into the decoder — both in
        // the same coordinate system (for latency estimation that stays
        // correct across input drops).
        std::atomic<uint64_t> frame_sample_pos{0};
        std::atomic<uint64_t> samples_in{0};
    };

    NtscDecoder(const Config& cfg, TripleBuffer& out);
    ~NtscDecoder();

    // Feed raw detected envelope samples.
    void process(const float* raw, size_t n);

    const Stats& stats() const { return stats_; }

private:
    enum class State { Search, Track };

    void decode_lines();
    void freerun_line(int64_t start);
    bool find_hsync_edge(double lo, double hi, double* edge_out,
                         int64_t* pulse_begin = nullptr,
                         int64_t* pulse_end = nullptr) const;
    void handle_line(double edge, bool edge_measured);
    void decode_row(double edge);
    void trim_buffers();

    // comp_/chromab_ hold the RAW detected envelope (and its bandpass);
    // accessors convert with the current AGC state. The chroma bandpass of
    // the affine raw->IRE map is a pure scale (the offset is DC-rejected).
    float ire(int64_t abs) const {
        return agc_.to_ire(comp_[static_cast<size_t>(abs - base_)]);
    }
    float ire_frac(double abs) const;
    float chroma_at(int64_t abs) const {
        return agc_.chroma_scale() *
               chromab_[static_cast<size_t>(abs - base_ + chroma_delay_)];
    }
    float chroma_frac(double abs) const;
    int64_t comp_end() const { return base_ + static_cast<int64_t>(comp_.size()); }
    int64_t chroma_end() const { return comp_end() - chroma_delay_; }

    const Config& cfg_;
    TripleBuffer& tb_;
    Stats stats_;

    double fs_;
    double nominal_period_;
    double omega_sc_;          // rad/sample of the color subcarrier
    int samples_per_us_;

    Agc agc_;
    LinePll pll_;
    State state_ = State::Search;

    // Composite (IRE) and chroma bandpass streams, absolute-indexed.
    std::vector<float> comp_;
    std::vector<float> chromab_;
    int64_t base_ = 0;
    int64_t chroma_delay_;
    FirFilterF chroma_bpf_;
    std::vector<float> uv_taps_;
    int uv_delay_;

    // Search state
    double search_prev_edge_ = -1.0;
    int64_t cursor_ = 0;
    int freerun_row_ = 0;  // "snow" rows painted while unlocked

    // Extent of the most recently found hsync pulse (slicer-asserted range).
    int64_t pulse_begin_ = 0;
    int64_t pulse_end_ = 0;

    // Vertical state
    int vsync_run_ = 0;
    int line_no_ = 0;
    uint64_t frame_seq_ = 0;

    // Per-line scratch
    std::vector<float> su_, sv_, suf_, svf_;

    FILE* dump_fp_ = nullptr;
};

}  // namespace famidec
