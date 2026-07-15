// Performance benchmark for the live RF pipeline (encoder + front-end + decoder).
// Replicates RfDecoderBridge.processFrame exactly and times each stage.
//
// Build:
//   clang++ -std=c++17 -O2 -I. test_rf_perf.cpp ntsc_encoder.cpp dsp/ntsc_decoder.cpp -o test_rf_perf
//   ./test_rf_perf
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "config.hpp"
#include "dsp/am_detector.hpp"
#include "dsp/dc_blocker.hpp"
#include "dsp/fir.hpp"
#include "dsp/frame.hpp"
#include "dsp/nco.hpp"
#include "dsp/ntsc_decoder.hpp"
#include "ntsc_encoder.hpp"

using namespace famidec;
using SteadyClock = std::chrono::steady_clock;
using dsec = std::chrono::duration<double>;

int main() {
    Config cfg;
    cfg.sample_rate = 10e6;
    cfg.offset_hz = 2.0e6;
    cfg.mode = Config::Mode::Color;

    const int w = 256, h = 240;
    std::vector<uint8_t> src(w * h * 4);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            size_t di = (static_cast<size_t>(y) * w + x) * 4;
            src[di + 0] = static_cast<uint8_t>(x);     // R gradient
            src[di + 1] = static_cast<uint8_t>(y);     // G gradient
            src[di + 2] = 128;                         // B
            src[di + 3] = 255;
        }

    RfEncoderParams ep;
    ep.sample_rate = cfg.sample_rate;
    ep.offset_hz = cfg.offset_hz;
    ep.lines_per_field = 262;
    ep.active_lines = 240;
    NtscRfEncoder enc(ep);

    TripleBuffer tb;
    NtscDecoder dec(cfg, tb);
    DcBlocker dcb;
    Nco mixer(cfg.offset_hz, cfg.sample_rate);
    FirFilterC lpf(design_lowpass(4.3e6, cfg.sample_rate, 31));
    EnvelopeDetector env;

    std::vector<std::complex<float>> iq;
    std::vector<float> comp;
    std::vector<uint8_t> decoded(Frame::kWidth * Frame::kHeight * 4);

    const int frames = 300;
    double tEnc = 0, tFE = 0, tDec = 0;

    for (int f = 0; f < frames; ++f) {
        auto t0 = SteadyClock::now();
        enc.encode_field(src.data(), w, h, iq);
        auto t1 = SteadyClock::now();
        for (size_t i = 0; i < iq.size(); ++i)
            iq[i] = dcb.process(iq[i]) * mixer.next();
        lpf.process(iq.data(), iq.data(), iq.size());
        comp.resize(iq.size());
        env.process(iq.data(), comp.data(), iq.size());
        auto t2 = SteadyClock::now();
        dec.process(comp.data(), comp.size());
        auto t3 = SteadyClock::now();
        const Frame* fr = tb.acquire();
        if (fr)
            std::copy(fr->rgba.data(),
                      fr->rgba.data() + fr->rgba.size(),
                      reinterpret_cast<uint32_t*>(decoded.data()));
        tEnc += dsec(t1 - t0).count();
        tFE += dsec(t2 - t1).count();
        tDec += dsec(t3 - t2).count();
    }

    std::printf("samples/frame: %zu\n", iq.size());
    std::printf("encode_field : %.2f ms/frame\n", 1000.0 * tEnc / frames);
    std::printf("front-end    : %.2f ms/frame\n", 1000.0 * tFE / frames);
    std::printf("decoder      : %.2f ms/frame\n", 1000.0 * tDec / frames);
    std::printf("TOTAL        : %.2f ms/frame  ->  %.1f fps\n",
                1000.0 * (tEnc + tFE + tDec) / frames,
                frames / (tEnc + tFE + tDec));

    // Sanity: the last decoded frame (copied into `decoded`) should be a real
    // (non-black) color, confirming the 31-tap LPF still yields a lockable RF
    // signal and a valid picture.
    const uint32_t* dp = reinterpret_cast<const uint32_t*>(decoded.data());
    uint32_t p = dp[static_cast<size_t>(Frame::kHeight / 2) * Frame::kWidth +
                    Frame::kWidth / 2];
    int r = p & 0xff, g = (p >> 8) & 0xff, b = (p >> 16) & 0xff;
    std::printf("decoded center px: (%d,%d,%d) %s\n", r, g, b,
                (r + g + b > 30) ? "OK" : "BLACK/garbage?");
    return 0;
}
