// End-to-end test of the NtscRfEncoder -> front-end -> NtscDecoder pipeline
// using a real (solid-color) source frame instead of synthetic color bars.
//
// Build:
//   clang++ -std=c++17 -I. test_rf_encoder.cpp ntsc_encoder.cpp dsp/ntsc_decoder.cpp -o test_rf_encoder
//   ./test_rf_encoder
#include <cmath>
#include <complex>
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

static std::vector<uint8_t> make_image(int w, int h, uint8_t r, uint8_t g,
                                       uint8_t b) {
    std::vector<uint8_t> img(static_cast<size_t>(w) * h * 4);
    for (size_t i = 0; i < img.size(); i += 4) {
        img[i] = r;
        img[i + 1] = g;
        img[i + 2] = b;
        img[i + 3] = 255;
    }
    return img;
}

static int sample_center(const Frame* f, int* r, int* g, int* b) {
    int px = Frame::kWidth / 2;
    int py = Frame::kHeight / 2;
    uint32_t v = f->rgba[static_cast<size_t>(py) * Frame::kWidth + px];
    *r = v & 0xff;
    *g = (v >> 8) & 0xff;
    *b = (v >> 16) & 0xff;
    return 0;
}

int main() {
    Config cfg;
    cfg.sample_rate = 10e6;
    cfg.offset_hz = 2.0e6;
    cfg.mode = Config::Mode::Color;

    RfEncoderParams ep;
    NtscRfEncoder enc(ep);

    DcBlocker dcb;
    Nco mixer(cfg.offset_hz, cfg.sample_rate);
    FirFilterC lpf(design_lowpass(4.3e6, cfg.sample_rate, 63));
    EnvelopeDetector env;
    TripleBuffer tb;
    NtscDecoder dec(cfg, tb);

    const int srcW = 256, srcH = 224;
    auto img = make_image(srcW, srcH, 200, 30, 30);  // reddish

    // Feed several fields so AGC/PLL lock before sampling.
    std::vector<std::complex<float>> iq;
    std::vector<float> comp;
    const int fields = 12;
    for (int fld = 0; fld < fields; ++fld) {
        enc.encode_field(img.data(), srcW, srcH, iq);
        for (size_t i = 0; i < iq.size(); ++i) iq[i] = dcb.process(iq[i]) * mixer.next();
        lpf.process(iq.data(), iq.data(), iq.size());
        comp.resize(iq.size());
        env.process(iq.data(), comp.data(), iq.size());
        dec.process(comp.data(), comp.size());
    }

    const Frame* f = tb.acquire();
    if (!f) {
        std::printf("FAIL: no frame\n");
        return 1;
    }
    int r, g, b;
    sample_center(f, &r, &g, &b);
    std::printf("decoded frames=%llu lines=%llu burst_amp=%.1f\n",
                static_cast<unsigned long long>(dec.stats().frames.load()),
                static_cast<unsigned long long>(dec.stats().lines.load()),
                dec.stats().burst_amp.load());
    std::printf("center pixel: got (%d,%d,%d)  expect reddish\n", r, g, b);

    int fails = 0;
    if (!(r > g + 40 && r > b + 40)) {
        std::printf("FAIL: not reddish enough\n");
        ++fails;
    }
    if (dec.stats().frames.load() < 5) {
        std::printf("FAIL: too few frames\n");
        ++fails;
    }

    // Gray-mode check: decoder should drop chroma.
    cfg.mode = Config::Mode::Gray;
    std::vector<uint8_t> img2 = make_image(srcW, srcH, 200, 30, 30);
    NtscRfEncoder enc2(ep);
    NtscDecoder dec2(cfg, tb);
    for (int fld = 0; fld < fields; ++fld) {
        enc2.encode_field(img2.data(), srcW, srcH, iq);
        for (size_t i = 0; i < iq.size(); ++i) iq[i] = dcb.process(iq[i]) * mixer.next();
        lpf.process(iq.data(), iq.data(), iq.size());
        env.process(iq.data(), comp.data(), iq.size());
        dec2.process(comp.data(), comp.size());
    }
    const Frame* f2 = tb.acquire();
    int gr, gg, gb;
    sample_center(f2, &gr, &gg, &gb);
    std::printf("gray-mode center: (%d,%d,%d)\n", gr, gg, gb);
    if (std::abs(gr - gg) > 12 || std::abs(gg - gb) > 12) {
        std::printf("FAIL: gray mode not neutral\n");
        ++fails;
    }

    if (fails) {
        std::printf("FAIL\n");
        return 1;
    }
    std::printf("PASS\n");
    return 0;
}
