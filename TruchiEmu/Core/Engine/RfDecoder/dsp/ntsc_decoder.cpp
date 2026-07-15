#include "ntsc_decoder.hpp"

#include <algorithm>
#include <cmath>

#include "chroma.hpp"

namespace famidec {

namespace {
constexpr float kSyncSliceIre = -20.0f;   // 50% of sync amplitude
constexpr float kMinBurstAmp = 3.0f;      // IRE; below this, decode gray
}  // namespace

NtscDecoder::NtscDecoder(const Config& cfg, TripleBuffer& out)
    : cfg_(cfg),
      tb_(out),
      fs_(cfg.sample_rate),
      nominal_period_(cfg.sample_rate / kLineRate),
      omega_sc_(2.0 * M_PI * kFsc / cfg.sample_rate),
      samples_per_us_(static_cast<int>(cfg.sample_rate / 1e6)),
      chroma_bpf_(design_bandpass(kFsc - 1.0e6, kFsc + 1.0e6, cfg.sample_rate, 41)),
      uv_taps_(design_lowpass(0.6e6, cfg.sample_rate, 31)) {
    pll_.init(nominal_period_);
    chroma_delay_ = static_cast<int64_t>(chroma_bpf_.delay());
    uv_delay_ = static_cast<int>((uv_taps_.size() - 1) / 2);
    if (!cfg.dump_composite_path.empty())
        dump_fp_ = std::fopen(cfg.dump_composite_path.c_str(), "wb");
}

NtscDecoder::~NtscDecoder() {
    if (dump_fp_) std::fclose(dump_fp_);
}

float NtscDecoder::ire_frac(double abs) const {
    int64_t i = static_cast<int64_t>(abs);
    double f = abs - static_cast<double>(i);
    float a = ire(i);
    float b = ire(i + 1);
    return a + static_cast<float>(f) * (b - a);
}

float NtscDecoder::chroma_frac(double abs) const {
    int64_t i = static_cast<int64_t>(abs);
    double f = abs - static_cast<double>(i);
    float a = chroma_at(i);
    float b = chroma_at(i + 1);
    return a + static_cast<float>(f) * (b - a);
}

void NtscDecoder::process(const float* raw, size_t n) {
    // Store RAW envelope; conversion to IRE happens at access time with the
    // current AGC state. (Storing converted values makes the per-line AGC
    // feedback act on stale mappings a whole block late — unstable.)
    size_t old = comp_.size();
    comp_.resize(old + n);
    std::copy(raw, raw + n, comp_.begin() + static_cast<long>(old));
    if (!agc_.seeded())
        for (size_t i = 0; i < n; ++i) agc_.bootstrap(raw[i]);
    if (dump_fp_) {
        static thread_local std::vector<float> tmp;
        tmp.resize(n);
        for (size_t i = 0; i < n; ++i) tmp[i] = agc_.to_ire(raw[i]);
        std::fwrite(tmp.data(), sizeof(float), n, dump_fp_);
    }
    chromab_.resize(old + n);
    chroma_bpf_.process(comp_.data() + old, chromab_.data() + old, n);

    stats_.samples_in.store(static_cast<uint64_t>(comp_end()),
                            std::memory_order_relaxed);
    if (agc_.seeded()) decode_lines();
    trim_buffers();
}

// Find an hsync leading edge (sync going low in IRE terms) in [lo, hi).
// Validates pulse width so vsync broad pulses are rejected.
bool NtscDecoder::find_hsync_edge(double lo, double hi, double* edge_out,
                                  int64_t* pulse_begin, int64_t* pulse_end) const {
    int64_t start = std::max(static_cast<int64_t>(lo), base_ + 1);
    int64_t end = std::min(static_cast<int64_t>(hi), comp_end() - 8 * samples_per_us_);
    for (int64_t j = start; j < end; ++j) {
        if (ire(j - 1) >= kSyncSliceIre && ire(j) < kSyncSliceIre) {
            // pulse width check: hsync is ~4.7 us
            int64_t k = j;
            int64_t maxw = j + 7 * samples_per_us_;
            while (k < maxw && ire(k) < kSyncSliceIre) ++k;
            int64_t w = k - j;
            if (w < 3 * samples_per_us_ || w > 6 * samples_per_us_) continue;
            // sub-sample interpolation of the threshold crossing
            float a = ire(j - 1), b = ire(j);
            double frac = (a - kSyncSliceIre) / (a - b);
            *edge_out = static_cast<double>(j - 1) + frac;
            if (pulse_begin) *pulse_begin = j;
            if (pulse_end) *pulse_end = k;
            return true;
        }
    }
    return false;
}

void NtscDecoder::decode_lines() {
    const int64_t margin = 60 + chroma_delay_;
    for (;;) {
        if (state_ == State::Search) {
            if (cursor_ < base_ + 1) cursor_ = base_ + 1;
            if (cursor_ + static_cast<int64_t>(2 * nominal_period_) + margin >=
                comp_end())
                return;
            double edge;
            if (!find_hsync_edge(static_cast<double>(cursor_),
                                 static_cast<double>(cursor_) + nominal_period_,
                                 &edge)) {
                // No sync anywhere in this line's worth of samples: paint it
                // as free-running "snow" so an unlocked signal is visible.
                freerun_line(cursor_);
                cursor_ += static_cast<int64_t>(nominal_period_);
                continue;
            }
            cursor_ = static_cast<int64_t>(edge) + 30 * samples_per_us_;
            if (search_prev_edge_ >= 0.0) {
                double interval = edge - search_prev_edge_;
                if (std::abs(interval - nominal_period_) <
                    0.02 * nominal_period_) {
                    pll_.acquire(edge, interval);
                    state_ = State::Track;
                    search_prev_edge_ = -1.0;
                    continue;
                }
            }
            search_prev_edge_ = edge;
        } else {
            // Need the full line plus search window and chroma delay.
            double predicted = pll_.next_edge;
            if (static_cast<int64_t>(predicted + pll_.period) + margin >=
                comp_end())
                return;
            double measured;
            bool ok = find_hsync_edge(predicted - 2 * samples_per_us_,
                                      predicted + 2 * samples_per_us_,
                                      &measured, &pulse_begin_, &pulse_end_);
            double edge = pll_.advance(ok, measured);
            if (!ok) stats_.lines_coasted.fetch_add(1, std::memory_order_relaxed);
            stats_.line_locked.store(pll_.locked, std::memory_order_relaxed);
            stats_.line_period.store(static_cast<float>(pll_.period),
                                     std::memory_order_relaxed);
            if (!pll_.locked && pll_.coast > LinePll::kCoastLimit) {
                state_ = State::Search;
                cursor_ = static_cast<int64_t>(edge);
                search_prev_edge_ = -1.0;
                continue;
            }
            handle_line(edge, ok);
            stats_.lines.fetch_add(1, std::memory_order_relaxed);
        }
    }
}

// Paint one unlocked line as grayscale snow, normalized per line so noise of
// any level is visible. Publishes a frame every kHeight/2 rows.
void NtscDecoder::freerun_line(int64_t start) {
    Frame& f = tb_.back();
    int row = freerun_row_ * 2;
    uint32_t* out0 = f.rgba.data() + static_cast<size_t>(row) * Frame::kWidth;
    uint32_t* out1 = out0 + Frame::kWidth;
    int64_t n = static_cast<int64_t>(nominal_period_);
    float lo = 1e30f, hi = -1e30f;
    for (int64_t j = start; j < start + n; ++j) {
        float v = comp_[static_cast<size_t>(j - base_)];
        lo = std::min(lo, v);
        hi = std::max(hi, v);
    }
    float scale = (hi > lo) ? 255.0f / (hi - lo) : 0.0f;
    double step = static_cast<double>(n) / Frame::kWidth;
    for (int px = 0; px < Frame::kWidth; ++px) {
        size_t idx = static_cast<size_t>(
            start + static_cast<int64_t>(px * step) - base_);
        auto g = static_cast<uint32_t>((comp_[idx] - lo) * scale);
        uint32_t px32 = 0xff000000u | (g << 16) | (g << 8) | g;
        out0[px] = px32;
        out1[px] = px32;
    }
    if (++freerun_row_ >= Frame::kHeight / 2) {
        freerun_row_ = 0;
        tb_.publish(++frame_seq_);
    }
}

void NtscDecoder::handle_line(double edge, bool edge_measured) {
    int64_t e = static_cast<int64_t>(std::llround(edge));
    int64_t period_i = static_cast<int64_t>(pll_.period);

    // Vsync: during the broad-pulse region, sync stays asserted most of the
    // line. Famicom emits no standard equalization, so just measure the
    // asserted fraction.
    int64_t asserted = 0;
    for (int64_t j = e; j < e + period_i; ++j)
        if (ire(j) < kSyncSliceIre) ++asserted;
    bool is_vsync_line =
        asserted > static_cast<int64_t>(0.45 * static_cast<double>(period_i));

    if (is_vsync_line) {
        ++vsync_run_;
        return;
    }
    if (vsync_run_ >= 2) {
        tb_.publish(++frame_seq_);
        stats_.frames.fetch_add(1, std::memory_order_relaxed);
        stats_.frame_sample_pos.store(static_cast<uint64_t>(e),
                                      std::memory_order_relaxed);
        line_no_ = 0;
    } else {
        ++line_no_;
        // Free-wheeling vertical sync: if noise made us miss the vsync
        // pulses, publish on the flywheel at the nominal field length so
        // frames keep flowing (a real TV does the same). Only while the
        // line PLL is solidly locked — otherwise a fake noise-lock would
        // publish black frames instead of falling back to snow.
        if (line_no_ >= 262) {
            if (pll_.locked) {
                tb_.publish(++frame_seq_);
                stats_.frames.fetch_add(1, std::memory_order_relaxed);
                stats_.frame_sample_pos.store(static_cast<uint64_t>(e),
                                              std::memory_order_relaxed);
            }
            line_no_ -= 262;
        }
    }
    vsync_run_ = 0;

    // AGC refinement: sync tip over the pulse, blanking from the back porch
    // after the burst (8.2..9.2 us).
    if (edge_measured && pulse_end_ > pulse_begin_) {
        // Average over the middle half of the slicer-asserted pulse extent.
        // Fixed offsets from the edge estimate drift onto the filter-ringing
        // overshoot as AGC scale errors bias the threshold crossing, which
        // turns the level feedback unstable.
        int64_t w = pulse_end_ - pulse_begin_;
        float tip = 0.0f;
        int tn = 0;
        for (int64_t j = pulse_begin_ + w / 4; j < pulse_end_ - w / 4; ++j, ++tn)
            tip += ire(j);
        tip /= static_cast<float>(tn);
        float blank = 0.0f;
        int n = 0;
        for (int64_t j = e + 82 * samples_per_us_ / 10;
             j < e + 92 * samples_per_us_ / 10; ++j, ++n)
            blank += ire(j);
        blank /= static_cast<float>(n);
        agc_.update_from_ire(tip, blank);
    }

    if (line_no_ >= kActiveStartLine &&
        line_no_ < kActiveStartLine + kActiveLines) {
        decode_row(edge);
    }
}

void NtscDecoder::decode_row(double edge) {
    Frame& f = tb_.back();
    int row = (line_no_ - kActiveStartLine) * 2;
    if (row < 0 || row + 1 >= Frame::kHeight) return;
    uint32_t* out0 = f.rgba.data() + static_cast<size_t>(row) * Frame::kWidth;
    uint32_t* out1 = out0 + Frame::kWidth;

    const double full_start = edge + 9.4 * samples_per_us_;
    const double full_span = 52.6 * samples_per_us_;
    // TV-style overscan: display only the central part of the active line.
    const double crop = full_span * cfg_.overscan;
    const double active_start = full_start + crop;
    const double active_span = full_span - 2.0 * crop;
    const double step = active_span / Frame::kWidth;
    const bool color = cfg_.mode == Config::Mode::Color;

    // Burst: ~9+ cycles starting 5.3 us after the edge; gate 3.2 us.
    BurstMeasurement burst;
    double phi = 0.0;
    if (color) {
        int64_t g0 = static_cast<int64_t>(std::llround(edge)) +
                     53 * samples_per_us_ / 10;
        int gn = 32 * samples_per_us_ / 10;
        static thread_local std::vector<float> gate;
        gate.resize(gn);
        for (int j = 0; j < gn; ++j) gate[j] = chroma_at(g0 + j);
        double theta0 = std::fmod(omega_sc_ * static_cast<double>(g0), 2.0 * M_PI);
        burst = measure_burst(gate.data(), gate.size(), theta0, omega_sc_,
                              kMinBurstAmp);
        stats_.burst_amp.store(burst.amplitude, std::memory_order_relaxed);
        phi = burst.phase + cfg_.hue_deg * M_PI / 180.0;
    }

    if (color && burst.valid) {
        // Demod U/V across the line (from just after the burst through the
        // end of active video plus the UV filter half-width).
        int64_t a0 = static_cast<int64_t>(std::llround(edge)) +
                     85 * samples_per_us_ / 10;
        int64_t a1 = static_cast<int64_t>(active_start + active_span) +
                     uv_delay_ + 2;
        size_t n = static_cast<size_t>(a1 - a0);
        su_.resize(n);
        sv_.resize(n);
        double th = std::fmod(omega_sc_ * static_cast<double>(a0), 2.0 * M_PI) + phi;
        for (size_t j = 0; j < n; ++j) {
            float c = chroma_at(a0 + static_cast<int64_t>(j));
            float s = std::sin(static_cast<float>(th));
            float co = std::cos(static_cast<float>(th));
            su_[j] = 2.0f * c * s;
            sv_[j] = 2.0f * c * co;
            th += omega_sc_;
            if (th > 2.0 * M_PI) th -= 2.0 * M_PI;
        }
        // Zero-history per-line LPF (edge transients land in blanking).
        size_t nt = uv_taps_.size();
        suf_.assign(n, 0.0f);
        svf_.assign(n, 0.0f);
        for (size_t i = nt - 1; i < n; ++i) {
            float au = 0.0f, av = 0.0f;
            for (size_t k = 0; k < nt; ++k) {
                au += su_[i - k] * uv_taps_[k];
                av += sv_[i - k] * uv_taps_[k];
            }
            suf_[i] = au;
            svf_[i] = av;
        }
        const float sat = cfg_.saturation;
        for (int px = 0; px < Frame::kWidth; ++px) {
            double p = active_start + px * step;
            float y = ire_frac(p) - chroma_frac(p);
            // filtered UV value centered at abs pos p
            int64_t idx = static_cast<int64_t>(p) - a0 + uv_delay_;
            float u = 0.0f, v = 0.0f;
            if (idx >= 0 && static_cast<size_t>(idx) < n) {
                u = suf_[static_cast<size_t>(idx)] * sat;
                v = svf_[static_cast<size_t>(idx)] * sat;
            }
            float yn = y / 100.0f, un = u / 100.0f, vn = v / 100.0f;
            float r = yn + 1.140f * vn;
            float g = yn - 0.395f * un - 0.581f * vn;
            float b = yn + 2.032f * un;
            auto q = [](float x) {
                return static_cast<uint32_t>(
                    std::clamp(x, 0.0f, 1.0f) * 255.0f + 0.5f);
            };
            uint32_t px32 = 0xff000000u | (q(b) << 16) | (q(g) << 8) | q(r);
            out0[px] = px32;
            out1[px] = px32;
        }
    } else {
        for (int px = 0; px < Frame::kWidth; ++px) {
            double p = active_start + px * step;
            float y = ire_frac(p) - chroma_frac(p);
            uint32_t g = static_cast<uint32_t>(
                std::clamp(y / 100.0f, 0.0f, 1.0f) * 255.0f + 0.5f);
            uint32_t px32 = 0xff000000u | (g << 16) | (g << 8) | g;
            out0[px] = px32;
            out1[px] = px32;
        }
    }
}

void NtscDecoder::trim_buffers() {
    // Keep enough history behind the decode position; drop the rest.
    int64_t keep_from;
    if (state_ == State::Track)
        keep_from = static_cast<int64_t>(pll_.next_edge) -
                    static_cast<int64_t>(nominal_period_);
    else
        keep_from = cursor_ - static_cast<int64_t>(nominal_period_);
    keep_from -= chroma_delay_ + 16;
    if (keep_from <= base_) return;
    size_t drop = static_cast<size_t>(keep_from - base_);
    if (drop < 32768 || drop > comp_.size()) return;
    comp_.erase(comp_.begin(), comp_.begin() + static_cast<long>(drop));
    chromab_.erase(chromab_.begin(), chromab_.begin() + static_cast<long>(drop));
    base_ += static_cast<int64_t>(drop);
}

}  // namespace famidec
