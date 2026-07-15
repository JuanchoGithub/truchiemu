#pragma once

#include <string>

namespace famidec {

struct Config {
    // RF
    double video_carrier_hz = 91.25e6;  // Japan VHF ch1
    double sample_rate = 10e6;
    double offset_hz = 2.0e6;  // center = carrier + offset (avoid DC spike)
    int lna_gain = 24;         // 0-40, step 8
    int vga_gain = 20;         // 0-62, step 2
    bool amp = false;

    enum class Input { HackRF, File };
    Input input = Input::HackRF;
    std::string file_path;
    bool loop = false;

    enum class Mode { Color, Gray };
    Mode mode = Mode::Color;

    enum class Detector { Envelope, SyncPLL };
    Detector detector = Detector::Envelope;

    std::string record_path;          // tee raw IQ to .cs8 while decoding
    std::string dump_composite_path;  // post-AGC composite as f32
    bool spectrum = false;            // PSD printout mode, no video
    bool headless = false;            // decode without SDL window (dump frames)
    std::string dump_frames_prefix;   // write decoded frames as PPM
    int dump_frame_count = 0;

    // Color trims
    float saturation = 1.0f;
    float hue_deg = 0.0f;

    // Horizontal overscan crop, fraction of the active line removed from
    // EACH side. Real TVs hide the edges; 0.047 ~ the NES 256-px picture.
    float overscan = 0.047f;

    // FM intercarrier audio (video +4.5 MHz)
    bool audio = true;
    float volume = 0.7f;

    double center_hz() const { return video_carrier_hz + offset_hz; }
};

}  // namespace famidec
