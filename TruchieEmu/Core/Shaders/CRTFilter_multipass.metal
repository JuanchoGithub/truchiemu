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

// --- [ UNIQUE HELPER FUNCTIONS ] ---

static inline CRT_MP_Context crt_mp_prepareContext(float2 screenUV, bool soft, bool chroma, bool vig, bool distort) {
    CRT_MP_Context ctx;
    if (soft || chroma || vig || distort) {
        ctx.centered = (screenUV - float2(0.5, 0.52)) * 2.0;
        ctx.centered *= float2(1.06, 1.08);
        ctx.distSq = dot(ctx.centered, ctx.centered);
    } else {
        ctx.centered = 0; ctx.distSq = 0;
    }
    return ctx;
}

static inline float2 crt_mp_getDistortedUV(float2 screenUV, CRT_MP_Context ctx, float amount, bool active) {
    if (!active) return screenUV;
    float2 offset = ctx.centered * ctx.centered;
    float2 distort = ctx.centered + (ctx.centered * (offset.yx * amount));
    return distort * 0.5 + 0.5;
}

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

    const bool DISTORT = u.useDistort > 0.5;
    const bool SCAN    = u.useScan > 0.5;
    const bool BLEED   = u.useBleed > 0.5;
    const bool SOFT    = u.useSoft > 0.5;
    const bool CHROMA  = u.useChroma > 0.5;
    const bool WHITE   = u.useWhite > 0.5;
    const bool VIG     = u.useVig > 0.5;
    const bool FLICK   = u.useFlick > 0.5;
    const bool BEZEL   = u.useBezel > 0.5;
    const bool BLOOM   = u.useBloom > 0.5;

    // 1. Preparation
    CRT_MP_Context ctx = crt_mp_prepareContext(in.texCoord, SOFT, CHROMA, VIG, DISTORT);

    // 2. Geometry
    float2 distortedUV = crt_mp_getDistortedUV(in.texCoord, ctx, u.barrelAmount, DISTORT);
    float2 sampleUV = distortedUV;
    sampleUV.y = distortedUV.y * CRT_MP_V_SCALE + CRT_MP_V_TRIM;
    
    float jitter = sin(in.position.y * 0.1 + u.time * 60.0) * CRT_MP_JITTER_AMOUNT;
    sampleUV.x += floor(jitter * 4096.0) * CRT_MP_INV_RES_X;

    // 3. Temporal Ghosting Samples
    float3 f0 = frame0.sample(s, sampleUV).rgb;
    float3 f1 = frame1.sample(s, sampleUV).rgb;
    float3 f2 = frame2.sample(s, sampleUV).rgb;
    float3 f3 = frame3.sample(s, sampleUV).rgb;
    float3 f4 = frame4.sample(s, sampleUV).rgb;

    // Apply spatial effects (Soft/Chroma) to f0 before mixing
    float blurAmt = SOFT ? (ctx.distSq * ctx.distSq) * 0.0008 : 0.0;
    float pShift = floor((0.0012 * ctx.distSq) * 4096.0) * CRT_MP_INV_RES_X;
    
    if (SOFT) f0.g = (f0.g + frame0.sample(s, sampleUV + float2(blurAmt)).g) * 0.5;
    
    if (CHROMA) {
        float chromaShift = pShift * (u.chromaAmount / 0.0012);
        f0.r = frame0.sample(s, sampleUV + float2(chromaShift, 0)).r;
        f0.b = frame0.sample(s, sampleUV - float2(chromaShift, 0)).b;
    }

    // 4. Phosphor Trail Mix (Exponential Decay)
    float3 trail = mix(f1, mix(f2, mix(f3, f4, 0.3), 0.4), 0.5);
    float3 rgb = mix(f0, trail, u.ghostingWeight);

    // 5. Analog Artifacts
    float spread = 1.0 / u.texSizeX;
    float3 colL = frame0.sample(s, sampleUV - float2(spread, 0)).rgb;
    float3 colR = frame0.sample(s, sampleUV + float2(spread, 0)).rgb;
    
    rgb = crt_mp_applyDitherBleed(rgb, colL, colR, BLEED);
    rgb = crt_mp_applyAnalogFinishing(rgb, ctx, u.colorBoost, float3(u.tintR, u.tintG, u.tintB), u.vignetteStrength, u.time, u.flickerStrength, WHITE, VIG, FLICK);
    
    if (SCAN) rgb = crt_mp_applyScanlines(rgb, f0, in.position.y, u.scanlineIntensity, u.bloomStrength, BLOOM);
    
    // 6. Final Composite
    float3 finalOut = crt_mp_applyMaskAndBezel(rgb, distortedUV, sampleUV, frame0, s, u.colorBoost, u.texSizeX, u.bezelRounding, u.bezelGlow, BEZEL);

    return float4(saturate(finalOut), 1.0);
}
