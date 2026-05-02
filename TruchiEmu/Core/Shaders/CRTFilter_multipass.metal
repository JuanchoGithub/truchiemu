#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

/**
 * CRT MULTIPASS SHADER (Phosphor Persistence Edition)
 * -------------------
 * Upgraded with 5-frame temporal ghosting to simulate phosphor decay.
 * All helper functions are uniquely namespaced (crt_mp_) to prevent linker errors.
 */

// --- [ PRE-COMPUTED CONSTANTS ] ---
constant float CRT_MP_JITTER_AMOUNT = 0.00015;
constant float CRT_MP_V_TRIM        = 0.033333;
constant float CRT_MP_V_SCALE       = 0.933334;
constant float CRT_MP_INV_RES_X     = 0.00024414;

// --- [ STRUCTURES ] ---

struct CRTMultipassUniforms {
    float scanlineIntensity;
    float barrelAmount;
    float colorBoost;
    float time;
    float ghostingWeight;    // NEW: Control for phosphor trail
    float bleedAmount;
    float texSizeX;
    float texSizeY;
    float vignetteStrength;
    float flickerStrength;
    float bloomStrength;
    float chromaAmount;
    float softnessAmount;
    float bezelRounding;
    float bezelGlow;
    float tintR;
    float tintG;
    float tintB;
    float useDistort;
    float useScan;
    float useBleed;
    float useSoft;
    float useChroma;
    float useWhite;
    float useVig;
    float useFlick;
    float useBezel;
    float useBloom;
    float padding;
};

struct CRT_MP_Context {
    float2 centered;
    float distSq;
};

static inline float3 crt_mp_applyDitherBleed(float3 rgb, float3 leftColor, float3 rightColor, bool active) {
    if (!active) return rgb;
    float3 bleed = (rgb + leftColor + rightColor) * 0.3;
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    return mix(mix(rgb, bleed, 2.0), rgb, 0.5 + (luma * 0.5));
}

static inline float3 crt_mp_applyAnalogFinishing(float3 rgb, CRT_MP_Context ctx, float boost, float3 tint, float vStr, float time, float fStr, bool useWhite, bool useVig, bool useFlick) {
    float3 out = rgb * (boost * 1.1);
    if (useWhite) out *= tint;
    if (useVig)   out *= saturate(1.0 - (ctx.distSq * vStr * vStr));
    if (useFlick) out *= (sin(time * 60.0) * fStr) + (1.0 - fStr);
    return out;
}

static inline float3 crt_mp_applyScanlines(float3 rgb, float3 sourceColor, float posY, float baseInt, float bloomStr, bool useBloom) {
    float scanline = sin(posY * 70.0) * 0.5 + 0.5;
    float intensity = baseInt;
    if (useBloom) {
        float luma = dot(sourceColor, float3(0.2126, 0.7152, 0.0722));
        intensity = mix(baseInt, 0.0, saturate(luma * bloomStr));
    }
    float scanPow = scanline * scanline * scanline;
    return rgb * mix(1.0, 1.0 - intensity, scanPow);
}

static inline float3 crt_mp_applyMaskAndBezel(float3 rgb, float2 distortUV, float2 sampleUV, texture2d<float> tex, sampler s, float boost, float texX, float rounding, float glowInt, bool bezel) {
    float2 maskEdge = abs(distortUV - 0.5) * 2.0;
    float cornerMask = pow(maskEdge.x, 12.0) + pow(maskEdge.y, 12.0); // Simplified high-order power for smooth rounding
    
    float tubeVis = 1.0 - smoothstep(1.0, 1.0 + rounding, cornerMask);
    if (distortUV.x < 0.0 || distortUV.x > 1.0 || distortUV.y < 0.0 || distortUV.y > 1.0) tubeVis = 0.0;

    float3 output = rgb * tubeVis;
    
    if (bezel && tubeVis < 0.99) {
        float glowWidth = 32.0 / texX;
        float2 adjustedEdge = maskEdge;
        float bezelW = (1.0 - tubeVis) * (1.0 - smoothstep(1.0, 1.0 + glowWidth, max(adjustedEdge.x, adjustedEdge.y)));

        if (bezelW > 0.001) {
            float2 mirUV = 1.0 - abs(1.0 - abs(sampleUV));
            output += tex.sample(s, mix(mirUV, sampleUV, 0.08)).rgb * boost * bezelW * glowInt;
        }
    }
    return output;
}

// --- [ MAIN FRAGMENT ] ---
fragment float4 fragmentCRTMultipass(VertexOut in [[stage_in]],
                            texture2d<float> frame0 [[texture(0)]],
                            texture2d<float> frame1 [[texture(1)]],
                            texture2d<float> frame2 [[texture(2)]],
                            texture2d<float> frame3 [[texture(3)]],
                            texture2d<float> frame4 [[texture(4)]],
                            constant CRTMultipassUniforms &u [[buffer(0)]]) {
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // 1. Geometry & Barrel Distortion
    float2 uv = in.texCoord;
    float2 centered = (uv - float2(0.5, 0.52)) * 2.0;
    centered *= float2(1.06, 1.08);
    float2 offset = centered * centered;
    
    float2 distortedUV = uv;
    if (u.useDistort > 0.5) {
        distortedUV = centered + (centered * (offset.yx * u.barrelAmount));
        distortedUV = distortedUV * 0.5 + 0.5;
    }

    // 2. Align Context
    float2 finalCentered = (distortedUV - 0.5) * 2.0;
    float distSq = dot(finalCentered, finalCentered);

    float2 sampleUV = distortedUV;
    sampleUV.y = distortedUV.y * CRT_MP_V_SCALE + CRT_MP_V_TRIM;
    
    float jitter = sin(in.position.y * 0.1 + u.time * 60.0) * CRT_MP_JITTER_AMOUNT;
    sampleUV.x += floor(jitter * 4096.0) * CRT_MP_INV_RES_X;

    // 3. Pre-calculate Chroma Offsets
    // This is the CRITICAL FIX: The entire temporal stack must use these.
    float2 uvR = sampleUV;
    float2 uvG = sampleUV;
    float2 uvB = sampleUV;

    if (u.useChroma > 0.5) {
        float pShift = floor((0.0012 * distSq) * 4096.0) * CRT_MP_INV_RES_X;
        float chromaShift = pShift * (u.chromaAmount / 0.0012);
        uvR.x += chromaShift;
        uvB.x -= chromaShift;
    }

    // 4. Sample Temporal Frames WITH Chroma Offsets
    // Since all frames use the shifted UVs, static objects will perfectly align with themselves.
    float3 f0 = float3(frame0.sample(s, uvR).r, frame0.sample(s, uvG).g, frame0.sample(s, uvB).b);
    float3 f1 = float3(frame1.sample(s, uvR).r, frame1.sample(s, uvG).g, frame1.sample(s, uvB).b);
    float3 f2 = float3(frame2.sample(s, uvR).r, frame2.sample(s, uvG).g, frame2.sample(s, uvB).b);
    float3 f3 = float3(frame3.sample(s, uvR).r, frame3.sample(s, uvG).g, frame3.sample(s, uvB).b);
    float3 f4 = float3(frame4.sample(s, uvR).r, frame4.sample(s, uvG).g, frame4.sample(s, uvB).b);

    // Phosphor Decay Mix
    float3 trail = mix(f1, mix(f2, mix(f3, f4, 0.3), 0.4), 0.5);
    float3 rgb = mix(f0, trail, u.ghostingWeight);

    // 5. Softness
    if (u.useSoft > 0.5) {
        float blurAmt = (distSq * distSq) * 0.0008;
        float gBlur = mix(frame0.sample(s, uvG + float2(blurAmt)).g,
                          frame1.sample(s, uvG + float2(blurAmt)).g, u.ghostingWeight);
        rgb.g = (rgb.g + gBlur) * 0.5;
    }

    // 6. Analog Finishing Passes
    float spread = 1.0 / u.texSizeX;
    float3 colL = frame0.sample(s, sampleUV - float2(spread, 0)).rgb;
    float3 colR = frame0.sample(s, sampleUV + float2(spread, 0)).rgb;
    
    rgb = crt_mp_applyDitherBleed(rgb, colL, colR, u.useBleed > 0.5);
    
    CRT_MP_Context alignedCtx;
    alignedCtx.centered = finalCentered;
    alignedCtx.distSq = distSq;

    rgb = crt_mp_applyAnalogFinishing(rgb, alignedCtx, u.colorBoost, float3(u.tintR, u.tintG, u.tintB), u.vignetteStrength, u.time, u.flickerStrength, u.useWhite > 0.5, u.useVig > 0.5, u.useFlick > 0.5);
    
    if (u.useScan > 0.5) rgb = crt_mp_applyScanlines(rgb, f0, in.position.y, u.scanlineIntensity, u.bloomStrength, u.useBloom > 0.5);
    
    float3 finalOut = crt_mp_applyMaskAndBezel(rgb, distortedUV, sampleUV, frame0, s, u.colorBoost, u.texSizeX, u.bezelRounding, u.bezelGlow, u.useBezel > 0.5);

    return float4(saturate(finalOut), 1.0);
}
