// Standalone golden test for the ported famidec RF decoder.
// Mirrors the upstream synth_ntsc test: synthesize an NTSC-J color-bar RF
// signal as int8 IQ, run it through the same DSP chain as the live pipeline,
// and assert the decoded RGB values match the transmitted bars.
//
// Build (no Xcode needed):
//   clang++ -std=c++17 -I. test_rf_golden.cpp dsp/ntsc_decoder.cpp -o test_rf_golden
//   ./test_rf_golden
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "config.hpp"
#include "dsp/am_detector.hpp"
#include "dsp/dc_blocker.hpp"
#include "dsp/fir.hpp"
#include "dsp/frame.hpp"
#include "dsp/nco.hpp"
#include "dsp/ntsc_decoder.hpp"

using namespace famidec;

namespace {

constexpr double kFs = 10e6;
constexpr double kFsc = 315e6 / 88.0;
constexpr double kLineUs = 1e6 / 15734.264;  // 63.555 us
constexpr int kLinesPerField = 262;
constexpr int kVsyncLines = 3;
constexpr int kPostVsyncBlank = 13;  // matches NtscDecoder::kActiveStartLine

struct Bar {
    float r, g, b;  // 0..1
};
const Bar kBars[7] = {
    {0.75f, 0.75f, 0.75f}, {0.75f, 0.75f, 0.0f}, {0.0f, 0.75f, 0.75f},
    {0.0f, 0.75f, 0.0f},   {0.75f, 0.0f, 0.75f}, {0.75f, 0.0f, 0.0f},
    {0.0f, 0.0f, 0.75f},
};

void yuv_of(const Bar& bar, float* y, float* u, float* v) {
    *y = 0.299f * bar.r + 0.587f * bar.g + 0.114f * bar.b;
    *u = 0.492f * (bar.b - *y);
    *v = 0.877f * (bar.r - *y);
}

// Composite IRE value at a given position within a field.
float composite_ire(int line, double us, double theta) {
    bool vsync_line = line < kVsyncLines;
    if (vsync_line) {
        // broad pulse: asserted except a 4.7 us serration at end of line
        return (us > kLineUs - 4.7) ? 0.0f : -40.0f;
    }
    if (us < 4.7) return -40.0f;                       // hsync
    if (us >= 5.3 && us < 7.8)                          // burst on back porch
        return -20.0f * static_cast<float>(std::sin(theta));
    if (us < 9.4 || us >= 62.0) return 0.0f;            // porches
    int active_line = line - kVsyncLines - kPostVsyncBlank;
    if (active_line < 0 || active_line >= 240) return 0.0f;  // blank line
    double frac = (us - 9.4) / 52.6;
    int bar_idx = std::min(6, static_cast<int>(frac * 7.0));
    float y, u, v;
    yuv_of(kBars[bar_idx], &y, &u, &v);
    float chroma = u * static_cast<float>(std::sin(theta)) +
                   v * static_cast<float>(std::cos(theta));
    return (y + chroma) * 100.0f;
}

}  // namespace

int main() {
    Config cfg;
    cfg.sample_rate = kFs;
    cfg.offset_hz = 2.0e6;
    cfg.mode = Config::Mode::Color;

    const int fields = 30;
    const size_t total = static_cast<size_t>(fields * kLinesPerField *
                                             kLineUs * kFs / 1e6);
    std::vector<uint8_t> iq(total * 2);
    const double omega_sc = 2.0 * M_PI * kFsc / kFs;
    const double omega_c = -2.0 * M_PI * cfg.offset_hz / kFs;
    const double samples_per_line = kFs * kLineUs / 1e6;
    const double samples_per_field = samples_per_line * kLinesPerField;
    for (size_t n = 0; n < total; ++n) {
        double in_field = std::fmod(static_cast<double>(n), samples_per_field);
        int line = static_cast<int>(in_field / samples_per_line);
        double us = std::fmod(in_field, samples_per_line) / kFs * 1e6;
        double theta = std::fmod(omega_sc * static_cast<double>(n), 2.0 * M_PI);
        float ire = composite_ire(line, us, theta);
        // Negative modulation: sync tip = 100% carrier, white = 12.5%.
        float amp = 0.75f - ire * (0.625f / 100.0f);
        double phase = omega_c * static_cast<double>(n);
        auto clip8 = [](float x) {
            return static_cast<int8_t>(std::lround(std::fmax(-127.0f, std::fmin(127.0f, x))));
        };
        iq[2 * n] = static_cast<uint8_t>(
            clip8(100.0f * amp * static_cast<float>(std::cos(phase))));
        iq[2 * n + 1] = static_cast<uint8_t>(
            clip8(100.0f * amp * static_cast<float>(std::sin(phase))));
    }

    TripleBuffer tb;
    NtscDecoder dec(cfg, tb);
    DcBlocker dcb;
    Nco mixer(cfg.offset_hz, kFs);
    FirFilterC lpf(design_lowpass(4.3e6, kFs, 63));
    EnvelopeDetector env;

    constexpr size_t kBlock = 32768;
    std::vector<std::complex<float>> cbuf(kBlock);
    std::vector<float> comp(kBlock);
    for (size_t off = 0; off < total; off += kBlock) {
        size_t ns = std::min(kBlock, total - off);
        for (size_t i = 0; i < ns; ++i) {
            std::complex<float> c(
                static_cast<int8_t>(iq[2 * (off + i)]) / 128.0f,
                static_cast<int8_t>(iq[2 * (off + i) + 1]) / 128.0f);
            cbuf[i] = dcb.process(c) * mixer.next();
        }
        lpf.process(cbuf.data(), cbuf.data(), ns);
        env.process(cbuf.data(), comp.data(), ns);
        dec.process(comp.data(), ns);
    }

    uint64_t frames = dec.stats().frames.load();
    std::printf("decoded frames: %llu, lines: %llu, coasted: %llu\n",
                static_cast<unsigned long long>(frames),
                static_cast<unsigned long long>(dec.stats().lines.load()),
                static_cast<unsigned long long>(dec.stats().lines_coasted.load()));
    if (frames < 10) {
        std::printf("FAIL: fewer than 10 frames decoded\n");
        return 1;
    }
    const Frame* f = tb.acquire();
    if (!f) {
        std::printf("FAIL: no frame available\n");
        return 1;
    }

    int failures = 0;
    for (int b = 0; b < 7; ++b) {
        int px = static_cast<int>((b + 0.5) / 7.0 * Frame::kWidth);
        int py = Frame::kHeight / 2;
        uint32_t p = f->rgba[static_cast<size_t>(py) * Frame::kWidth + px];
        int r = p & 0xff, g = (p >> 8) & 0xff, bl = (p >> 16) & 0xff;
        int er = static_cast<int>(kBars[b].r * 255.0f + 0.5f);
        int eg = static_cast<int>(kBars[b].g * 255.0f + 0.5f);
        int eb = static_cast<int>(kBars[b].b * 255.0f + 0.5f);
        int tol = 35;
        bool ok = std::abs(r - er) <= tol && std::abs(g - eg) <= tol &&
                  std::abs(bl - eb) <= tol;
        std::printf("bar %d: got (%3d,%3d,%3d) expect (%3d,%3d,%3d) %s\n", b,
                    r, g, bl, er, eg, eb, ok ? "OK" : "FAIL");
        if (!ok) ++failures;
    }
    if (failures) {
        std::printf("FAIL: %d bars out of tolerance\n", failures);
        return 1;
    }
    std::printf("PASS\n");
    return 0;
}
