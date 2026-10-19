#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

/*
 * CRT Shader — Metal port of crt-shader.
 *
 * Original implementation and package: Brooklyn (OutThisLife)
 * https://crt-shader.vercel.app
 * https://github.com/OutThisLife/crt-shader
 *
 * MIT License
 *
 * Copyright (c) 2026 Brooklyn (OutThisLife)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Visual inspiration: Datagubbe, "The Effect of CRTs on Pixel Art"
 * https://datagubbe.se/crt/
 *
 * Port notes:
 * - The source runs horizontal -> vertical -> optics at W x Sh, W x H, W x H.
 *   MetalCoordinator keeps that three-stage order with two intermediate
 *   textures and the final optics pass in the drawable.
 * - The source uses GL bottom-left fragment coordinates. This port uses the
 *   top-left Metal convention and offsets the mask math by outputOrigin.
 * - The source aspect setting controls host layout only. TruchiEmu already
 *   letterboxes through the viewport, so it is not in this uniform block.
 */

// Field order must match CRTShaderUniforms in ShaderUniforms.swift exactly.
struct CRTShaderUniforms {
    float spread;
    float bleed;
    float gamma;
    float beam;
    float bloom;
    float glow;
    float focus;
    float mask;
    float exposure;
    float outputGamma;
    float cameraBlur;
    float blackLevel;
    float redGain;
    float greenGain;
    float blueGain;
    float maskPitch;
    float maskPhase;
    float slot;
    float slotPhase;
    float maskSlant;
    float beamTilt;
    float maskWarp;
    float rg;
    float rb;
    float gr;
    float gb;
    float br;
    float bg;
    float sourceW;
    float sourceH;
    float outputW;
    float outputH;
    float outputOriginX;
    float outputOriginY;
};

static inline float crtGaussian(float d, float s) {
    float safeSigma = max(s, 0.0001f);
    return exp(-0.5f * d * d / (safeSigma * safeSigma));
}

static inline float3 crtSampleBlack(texture2d<float> tex, sampler s, float2 uv) {
    if (any(uv < 0.0f) || any(uv >= 1.0f)) {
        return float3(0.0f);
    }
    return tex.sample(s, uv).rgb;
}

// PASS 1: horizontal luminance spread + chroma bleed.
fragment float4 fragmentCRTShaderHorizontal(VertexOut in [[stage_in]],
                                            texture2d<float> tex [[texture(0)]],
                                            constant CRTShaderUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge, mip_filter::none);

    float x = in.texCoord.x * u.sourceW - 0.5f;
    float base = floor(x);
    float3 color = float3(0.0f);
    float light = 0.0f;
    float wl = 0.0f;
    float wc = 0.0f;

    for (int i = -7; i <= 7; ++i) {
        float at = base + float(i);
        float d = at - x;
        float3 sample = pow(
            crtSampleBlack(tex, s, float2((at + 0.5f) / u.sourceW, in.texCoord.y)),
            float3(u.gamma));
        float l = dot(sample, float3(0.2126f, 0.7152f, 0.0722f));
        float a = crtGaussian(d, u.spread);
        float b = crtGaussian(d, u.spread + u.bleed);
        light += l * a;
        wl += a;
        color += (sample - float3(l)) * b;
        wc += b;
    }

    float3 result = max(float3(light / max(wl, 0.0001f)) + color / max(wc, 0.0001f),
                        float3(0.0f));
    return float4(result, 1.0f);
}

// PASS 2: electron beam, bloom, scanline mask.
fragment float4 fragmentCRTShaderVertical(VertexOut in [[stage_in]],
                                          texture2d<float> tex [[texture(0)]],
                                          constant CRTShaderUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge, mip_filter::none);

    float pixelScale = u.outputW / u.sourceW;
    float y = in.texCoord.y * u.sourceH - 0.5f
        - u.beamTilt * in.texCoord.x * u.outputW * u.sourceH / u.outputH;
    float base = floor(y);
    float3 c = float3(0.0f);

    for (int j = -3; j <= 3; ++j) {
        float row = base + float(j);
        float3 sample = crtSampleBlack(
            tex, s, float2(in.texCoord.x, (row + 0.5f) / u.sourceH));
        // Width grows with signal intensity; integral stays constant.
        float3 width = float3(u.beam) + u.bloom * sqrt(max(sample, float3(0.0f)));
        float3 d = float3(y - row) / width;
        c += sample * exp(-0.5f * d * d) / (2.506628f * width);
    }

    float fx = in.position.x - u.outputOriginX;
    float fy = in.position.y - u.outputOriginY;
    float cell = fmod(floor(fx), 3.0f);
    float3 grille;
    if (cell < 1.0f) {
        grille = float3(1.0f, 1.0f - u.mask, 1.0f - u.mask);
    } else if (cell < 2.0f) {
        grille = float3(1.0f - u.mask, 1.0f, 1.0f - u.mask);
    } else {
        grille = float3(1.0f - u.mask, 1.0f - u.mask, 1.0f);
    }

    if (u.maskPitch > 0.0f) {
        float wave = (fx + u.maskSlant * fy) / (u.maskPitch * pixelScale)
            + u.maskWarp * in.texCoord.x * in.texCoord.x;
        float3 phase = wave + u.maskPhase - float3(0.0f, 1.0f / 3.0f, 2.0f / 3.0f);
        float3 stripes = pow(0.5f + 0.5f * cos(6.2831853f * phase), float3(2.0f));
        c *= ((1.0f - u.mask) + u.mask * stripes) / (1.0f - 0.625f * u.mask);
        float slots = 0.5f + 0.5f * cos(6.2831853f * (wave + u.slotPhase));
        c *= ((1.0f - u.slot) + u.slot * slots) / (1.0f - 0.5f * u.slot);
    } else {
        c *= grille / (1.0f - 2.0f * u.mask / 3.0f);
    }

    return float4(c, 1.0f);
}

// PASS 3: optics, color calibration, highlight shoulder, output transfer.
fragment float4 fragmentCRTShaderOptics(VertexOut in [[stage_in]],
                                        texture2d<float> tex [[texture(0)]],
                                        constant CRTShaderUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, mip_filter::none);

    float2 pixel = float2(1.0f / u.sourceW, 1.0f / u.sourceH);
    float3 sharp = tex.sample(s, in.texCoord).rgb;
    float2 f = u.focus * pixel;

    float3 soft = sharp * 0.25f;
    soft += (crtSampleBlack(tex, s, in.texCoord + float2(f.x, 0.0f))
        + crtSampleBlack(tex, s, in.texCoord - float2(f.x, 0.0f))
        + crtSampleBlack(tex, s, in.texCoord + float2(0.0f, f.y))
        + crtSampleBlack(tex, s, in.texCoord - float2(0.0f, f.y))) * 0.125f;
    soft += (crtSampleBlack(tex, s, in.texCoord + f)
        + crtSampleBlack(tex, s, in.texCoord - f)
        + crtSampleBlack(tex, s, in.texCoord + float2(f.x, -f.y))
        + crtSampleBlack(tex, s, in.texCoord + float2(-f.x, f.y))) * 0.0625f;

    float2 g = pixel * 1.1f;
    float3 halo = (crtSampleBlack(tex, s, in.texCoord + float2(g.x, 0.0f))
        + crtSampleBlack(tex, s, in.texCoord - float2(g.x, 0.0f))
        + crtSampleBlack(tex, s, in.texCoord + float2(0.0f, g.y))
        + crtSampleBlack(tex, s, in.texCoord - float2(0.0f, g.y))) * 0.25f;

    if (u.cameraBlur > 0.0f) {
        soft = float3(0.0f);
        float total = 0.0f;
        float2 tap = u.cameraBlur * (u.outputW / u.sourceW)
            / (1.2f * float2(u.outputW, u.outputH));
        for (int j = -3; j <= 3; ++j) {
            for (int i = -3; i <= 3; ++i) {
                float w = exp(-0.5f * float(i * i + j * j) / (1.2f * 1.2f));
                soft += crtSampleBlack(
                    tex, s, in.texCoord + float2(float(i), float(j)) * tap) * w;
                total += w;
            }
        }
        soft /= total;
    }

    float3 c = (soft + halo * u.glow) * u.exposure
        * float3(u.redGain, u.greenGain, u.blueGain);
    c = max(float3(dot(c, float3(1.0f, u.rg, u.rb)),
                   dot(c, float3(u.gr, 1.0f, u.gb)),
                   dot(c, float3(u.br, u.bg, 1.0f))),
            float3(0.0f));
    // Gentle highlight shoulder, preserving most of the original contrast.
    c = c / (1.0f + max(c - float3(0.8f), float3(0.0f)) * 0.35f);

    float transferGamma = u.outputGamma > 0.0f ? u.outputGamma : u.gamma;
    float3 result = pow(max(c, float3(0.0f)), float3(1.0f / transferGamma))
        * (1.0f - u.blackLevel) + u.blackLevel;
    return float4(result, 1.0f);
}
