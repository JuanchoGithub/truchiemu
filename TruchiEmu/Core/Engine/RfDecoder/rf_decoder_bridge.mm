#import "rf_decoder_bridge.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <random>
#include <vector>

#include "config.hpp"
#include "dsp/am_detector.hpp"
#include "dsp/dc_blocker.hpp"
#include "dsp/fir.hpp"
#include "dsp/frame.hpp"
#include "dsp/nco.hpp"
#include "dsp/ntsc_decoder.hpp"
#include "ntsc_encoder.hpp"
#include "rf_dynamic_state.h"

using namespace famidec;

namespace {

// Convert a libretro pixel buffer (as interpreted by the existing texture
// upload path: format 1 -> BGRA8 in memory, format 0 -> A1BGR5, format 2 ->
// B5G6R5) into a tightly-packed RGBA8 buffer for the encoder.
void convert_to_rgba8(const uint8_t* src, int w, int h, int pitch, int bpp,
                      int format, std::vector<uint8_t>& out) {
    out.resize(static_cast<size_t>(w) * h * 4);
    for (int y = 0; y < h; ++y) {
        const uint8_t* row = src + static_cast<size_t>(y) * pitch;
        for (int x = 0; x < w; ++x) {
            size_t di = (static_cast<size_t>(y) * w + x) * 4;
            if (bpp == 4) {
                // Memory layout is BGRA (format 1, XRGB8888 mapped to BGRA8).
                out[di + 0] = row[x * 4 + 2];  // R
                out[di + 1] = row[x * 4 + 1];  // G
                out[di + 2] = row[x * 4 + 0];  // B
                out[di + 3] = row[x * 4 + 3];  // A
            } else if (bpp == 2) {
                uint16_t v = *reinterpret_cast<const uint16_t*>(row + x * 2);
                int r, g, b;
                if (format == 0) {  // a1bgr5: A B(5) G(5) R(5)
                    r = (v & 0x1F) * 255 / 31;
                    g = ((v >> 5) & 0x1F) * 255 / 31;
                    b = ((v >> 10) & 0x1F) * 255 / 31;
                } else {  // b5g6r5: B(5) G(6) R(5)
                    r = ((v >> 11) & 0x1F) * 255 / 31;
                    g = ((v >> 5) & 0x3F) * 255 / 63;
                    b = (v & 0x1F) * 255 / 31;
                }
                out[di + 0] = static_cast<uint8_t>(r);
                out[di + 1] = static_cast<uint8_t>(g);
                out[di + 2] = static_cast<uint8_t>(b);
                out[di + 3] = 255;
            } else {  // 8-bit single channel (e.g. r8) -> grayscale
                uint8_t v = row[x * bpp];
                out[di + 0] = v;
                out[di + 1] = v;
                out[di + 2] = v;
                out[di + 3] = 255;
            }
        }
    }
}

}  // namespace

@implementation RfDecoderBridge {
    famidec::Config _cfg;
    std::unique_ptr<famidec::TripleBuffer> _tb;
    std::unique_ptr<famidec::NtscRfEncoder> _enc;
    std::unique_ptr<famidec::NtscDecoder> _dec;
    famidec::DcBlocker _dcb;
    std::unique_ptr<famidec::Nco> _mixer;
    std::unique_ptr<famidec::FirFilterC> _lpf;
    famidec::EnvelopeDetector _env;

    std::vector<std::complex<float>> _iq;
    std::vector<float> _comp;
    std::vector<uint8_t> _srcRGBA;
    std::vector<uint8_t> _decoded;  // 640*480*4

    int _srcW, _srcH;
    bool _configured;

    // UI base RF knobs (never mutated by the event logic, so modulations
    // don't accumulate frame-over-frame).
    float _baseSignal, _baseSnow, _baseTuning, _baseGhost;
    float _instability;

    // Auto "bad reception" event scheduler.
    uint64_t _frameNo;
    int _evType;        // 0 none, 1 dropout, 2 roll, 3 bump, 4 tune
    int _evT;           // elapsed frames in current event
    int _evDur;         // event duration (frames)
    float _evInt;       // event intensity 0..1
    float _rollPhase;   // current vertical roll offset (fraction, wraps)
    float _rollSpeedEvt; // extra roll speed during a roll/bump event
    std::mt19937 _erng;
    std::mutex _lock;   // guards reallocating _enc/_dec/_tb (reset) vs use
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cfg.sample_rate = 10e6;
        _cfg.offset_hz = 2.0e6;
        _cfg.mode = famidec::Config::Mode::Color;
        _cfg.saturation = 1.0f;
        _cfg.hue_deg = 0.0f;
        _cfg.overscan = 0.047f;
        _mixer = std::make_unique<famidec::Nco>(_cfg.offset_hz, _cfg.sample_rate);
        _lpf = std::make_unique<famidec::FirFilterC>(
            famidec::design_lowpass(4.3e6, _cfg.sample_rate, 31));
        _srcW = 0;
        _srcH = 0;
        _configured = false;
        _baseSignal = 1.0f;
        _baseSnow = 0.0f;
        _baseTuning = 0.0f;
        _baseGhost = 0.0f;
        _instability = 0.5f;
        _frameNo = 0;
        _evType = 0;
        _evT = 0;
        _evDur = 0;
        _evInt = 0.0f;
        _rollPhase = 0.0f;
        _rollSpeedEvt = 0.0f;
        _erng.seed(0x1234567u);
        [self reset];
    }
    return self;
}

- (void)configureWithWidth:(int)srcW height:(int)srcH {
    if (srcW == _srcW && srcH == _srcH && _configured) return;
    _srcW = srcW;
    _srcH = srcH;
    _configured = true;

    RfEncoderParams ep;
    ep.sample_rate = _cfg.sample_rate;
    ep.offset_hz = _cfg.offset_hz;
    ep.lines_per_field = 262;
    ep.vsync_lines = 3;
    ep.active_start_line = 13;
    ep.active_lines = 240;  // decoder expectation; source height scaled in
    _enc = std::make_unique<famidec::NtscRfEncoder>(ep);

    _tb = std::make_unique<famidec::TripleBuffer>();
    _dec = std::make_unique<famidec::NtscDecoder>(_cfg, *_tb);
    _decoded.assign(famidec::Frame::kWidth * famidec::Frame::kHeight * 4, 0);
}

- (void)setSignalStrength:(float)signalStrength
                      snow:(float)snow
                  tuningHz:(float)tuningHz
                  ghosting:(float)ghosting
                saturation:(float)saturation
                   hueDeg:(float)hueDeg
                 colorMode:(int)colorMode
                instability:(float)instability {
    std::lock_guard<std::mutex> lk(_lock);
    _baseSignal = signalStrength;
    _baseSnow = snow;
    _baseTuning = tuningHz;
    _baseGhost = ghosting;
    _instability = instability;
    if (_enc) _enc->set_rf_knobs(signalStrength, snow, tuningHz, ghosting);
    _cfg.saturation = saturation;
    _cfg.hue_deg = hueDeg;
    _cfg.mode = (colorMode > 0.5f) ? famidec::Config::Mode::Color
                                   : famidec::Config::Mode::Gray;
}

// Advance the auto "bad reception" event scheduler and publish both the RF-knob
// modulations (so the real decoder produces snow / moire / ghosting) and the
// display-stage effects (grey static, vertical roll, diagonal shear, tear,
// bump glitches) consumed by the RfDisplay Metal pass.
- (void)updateInstability {
    _frameNo += 1;
    float inst = _instability;

    // Smooth ramp envelope over the first/last 15% of an event.
    auto envelope = [](int t, int dur) -> float {
        if (dur <= 1) return 1.0f;
        float f = static_cast<float>(t) / static_cast<float>(dur);
        float e = std::min(f, 1.0f - f) * 6.6667f;
        return std::max(0.0f, std::min(1.0f, e));
    };
    // C++ lambda (captures _erng by reference) so the RNG actually advances.
    auto erf = [&]() -> float { return static_cast<float>(_erng()) / 4294967295.0f; };

    // Schedule / advance events. Frequency scales with instability so low
    // values almost never fire; intensity is also scaled by `inst` below so
    // a value like 0.01 produces only a barely-perceptible wobble, never a
    // full dropout / roll / grey-snow event.
    if (_evType == 0) {
        float p = 0.02f * inst * inst;
        if (inst > 0.001f && erf() < p) {
            int pick = static_cast<int>(erf() * 4.0f);
            if (pick == 0)      { _evType = 1; _evDur = 20 + static_cast<int>(erf() * 50); }
            else if (pick == 1) { _evType = 2; _evDur = 40 + static_cast<int>(erf() * 90); }
            else if (pick == 2) { _evType = 3; _evDur = 6 + static_cast<int>(erf() * 16); }
            else                { _evType = 4; _evDur = 25 + static_cast<int>(erf() * 45); }
            _evT = 0;
            _evInt = 0.6f + erf() * 0.4f;  // 0.6..1.0 base
        }
    } else {
        _evT += 1;
        if (_evT >= _evDur) {
            _evType = 0;
            _evT = 0;
            _rollSpeedEvt = 0.0f;
        }
    }

    // Vertical roll is driven only by active instability events (roll/bump);
    // when idle the picture eases back to neutral (rollOffset -> 0) so there
    // is no constant creeping drift. Movement can still happen during events,
    // it just settles afterward.
    if (_evType != 0) {
        _rollPhase += _rollSpeedEvt;
    } else {
        _rollPhase *= 0.9f;
        if (std::fabs(_rollPhase) < 0.001f) _rollPhase = 0.0f;
    }
    if (_rollPhase >= 1.0f) _rollPhase -= 1.0f;
    else if (_rollPhase < 0.0f)  _rollPhase += 1.0f;

    // Effective event intensity scales with instability: at low `inst` the
    // same scheduled event is a faint nudge, at high `inst` it's a full hit.
    float ei = _evInt * inst;

    // Per-event reception targets. Fading the carrier (targetSignal -> 0)
    // drives the *real* decoder: weak burst -> automatic B&W, no sync ->
    // genuine grey "snow". The display-stage values add the rolling / tear /
    // bump glitch flavor on top.
    float targetSignal = 1.0f;   // 1 = full carrier, 0 = off-air
    float targetSnow = 0.0f;
    float tuneSweep = 0.0f;
    float shear = 0.0f;
    float glitch = 0.0f, tear = 0.0f;
    float hShift = 0.0f;

    if (_evType == 1) {                 // carrier dropout -> off-air grey snow
        float e = envelope(_evT, _evDur);
        targetSignal = 1.0f - 0.97f * e * ei;   // down to ~0.03
        targetSnow = 0.8f * e * ei;
    } else if (_evType == 2) {          // vertical hold loss -> weak + rolling
        float e = envelope(_evT, _evDur);
        targetSignal = 1.0f - 0.72f * e * ei;   // ~0.28 -> burst drops -> B&W
        targetSnow = 0.45f * e * ei;
        shear = 0.09f * e * ei;                 // diagonal drift
        _rollSpeedEvt = 0.014f * e * ei;
    } else if (_evType == 3) {          // bump -> brief, everything at once
        float e = envelope(_evT, _evDur);
        targetSignal = 1.0f - 0.88f * e * ei;
        targetSnow = 0.6f * e * ei;
        glitch = ei * e;
        tear = ei * e;
        hShift = (erf() - 0.5f) * 2.0f * ei * e;
        tuneSweep = 8000.0f * ei * e;
        _rollSpeedEvt = 0.035f * e * ei;
    } else if (_evType == 4) {          // tuning drift sweep (herringbone + B&W)
        float e = envelope(_evT, _evDur);
        targetSignal = 1.0f - 0.6f * e * ei;    // weak -> B&W
        targetSnow = 0.35f * e * ei;
        tuneSweep = ei * 11000.0f * std::sin(static_cast<float>(_evT) * 0.35f) * e;
    }

    // Effective RF knobs layered on the UI base values. Signal never drops
    // below 0.2 (keeps the decoder off true off-air so it can't fully collapse
    // to grey snow via the UI), and finer stepping lets instability modulate
    // it subtly.
    float flick = 0.04f * inst * erf();   // tiny always-on carrier flutter
    float effSignal = _baseSignal * targetSignal * (1.0f - flick);
    if (effSignal < 0.2f) effSignal = 0.2f;
    float effSnow = _baseSnow + targetSnow;
    float effGhost = _baseGhost + glitch * 0.4f + targetSnow * 0.2f;
    _enc->set_rf_knobs(effSignal, effSnow, _baseTuning + tuneSweep, effGhost);

    // Display-stage "signal loss" overlay tracks how far the carrier faded.
    float signalLoss = 1.0f - effSignal / std::max(_baseSignal, 0.2f);
    signalLoss = std::max(signalLoss, targetSnow * 0.6f);
    signalLoss = std::max(0.0f, std::min(1.0f, signalLoss));
    shear = std::max(0.0f, std::min(0.25f, shear));
    glitch = std::max(0.0f, std::min(1.0f, glitch));
    tear = std::max(0.0f, std::min(1.0f, tear));
    hShift = std::max(-1.0f, std::min(1.0f, hShift));

    RfDynamicState s;
    s.signalLoss = signalLoss;
    s.rollOffset = _rollPhase;
    s.rollShear = shear;
    s.glitch = glitch;
    s.tear = tear;
    s.hShift = hShift;
    s.frame = _frameNo;
    RfDynamicStateSet(&s);
}

- (void)processFrame:(const void*)data
                width:(int)w
               height:(int)h
                pitch:(int)pitch
                  bpp:(int)bpp
                format:(int)format {
    std::lock_guard<std::mutex> lk(_lock);
    if (!data || w <= 0 || h <= 0) return;
    [self configureWithWidth:w height:h];
    if (!_enc || !_dec) return;

    [self updateInstability];

    convert_to_rgba8(static_cast<const uint8_t*>(data), w, h, pitch, bpp,
                     format, _srcRGBA);

    _enc->encode_field(_srcRGBA.data(), w, h, _iq);
    for (size_t i = 0; i < _iq.size(); ++i)
        _iq[i] = _dcb.process(_iq[i]) * _mixer->next();
    _lpf->process(_iq.data(), _iq.data(), _iq.size());
    _comp.resize(_iq.size());
    _env.process(_iq.data(), _comp.data(), _iq.size());
    _dec->process(_comp.data(), _comp.size());

    const famidec::Frame* f = _tb->acquire();
    if (f) {
        const uint8_t* src = reinterpret_cast<const uint8_t*>(f->rgba.data());
        std::copy(src, src + f->rgba.size() * sizeof(uint32_t), _decoded.begin());
    }
}

- (const uint8_t*)decodedRGBA {
    return _decoded.empty() ? nullptr : _decoded.data();
}

- (int)decodedWidth {
    return famidec::Frame::kWidth;
}

- (int)decodedHeight {
    return famidec::Frame::kHeight;
}

- (void)reset {
    std::lock_guard<std::mutex> lk(_lock);
    _tb = std::make_unique<famidec::TripleBuffer>();
    _dec = std::make_unique<famidec::NtscDecoder>(_cfg, *_tb);
    if (_enc) _enc->reset_state();
    _decoded.assign(famidec::Frame::kWidth * famidec::Frame::kHeight * 4, 0);
}

@end
