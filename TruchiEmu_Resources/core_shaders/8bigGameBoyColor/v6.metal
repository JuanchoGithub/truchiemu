/*
 * TruchiEmu: 8bit Game Boy Color Hardware Simulation
 * VERSION HISTORY:
 * v17.8: Hybrid Elite Effects Port
 * - Added Power LED flicker effect (left edge glow)
 * - Added Polarizer moiré pattern
 * - Added Grain film noise
 * - Fixed unitF.x scalar arithmetic in grid
 * Developed by JayJay & Gemini
 */

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// --- FEATURE FLAGS ---
#define FLAG_GHOSTING      (1 << 0)
#define FLAG_GRID          (1 << 1)
#define FLAG_ABERRATION    (1 << 2)
#define FLAG_BLEED         (1 << 3)
#define FLAG_NEWTON_RINGS  (1 << 4)
#define FLAG_JITTER        (1 << 5)
#define FLAG_REFLECTION    (1 << 6)

struct GBCUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float physicalDepth;
    float ghostingWeight;
    uint  frameIndex;
    uint  flags;
};

// --- SIMULATION MODULES ---

float pcg_hash_gbc(float2 p) {
    uint2 v = uint2(p);
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    return float(v.x) * (1.0 / 4294967296.0);
}

float3 get_aberration(texture2d<float> tex, sampler s, float2 uv, float sqDist) {
    float abOffset = 0.0006 * sqDist;
    float4 rS = tex.sample(s, uv + float2(abOffset, 0.0));
    float4 gS = tex.sample(s, uv);
    float4 bS = tex.sample(s, uv - float2(abOffset, 0.0));
    return float3(rS.r, gS.g, bS.b);
}

float3 apply_ghosting(float3 f0, float3 f1, float3 f2, float3 f3, float3 f4, float p) {
    float3 s1 = mix(f0, f1, p);
    float3 s2 = mix(s1, f2, p * 0.85);
    float3 s3 = mix(s2, f3, p * 0.70);
    float3 s4 = mix(s3, f4, p * 0.50);
    return float3(s4.r, s4.g, s4.b);
}

// --- MAIN FRAGMENT SHADER ---

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> frame0 [[texture(0)]],
                                texture2d<float> frame1 [[texture(1)]],
                                texture2d<float> frame2 [[texture(2)]],
                                texture2d<float> frame3 [[texture(3)]],
                                texture2d<float> frame4 [[texture(4)]],
                                constant GBCUniforms &u [[buffer(0)]]) {
    
    const float2 gbcRes = float2(160.0, 144.0);
    float2 uv = in.texCoord;
    float2 centeredUV = uv - float2(0.5, 0.5);
    float sqDist = dot(centeredUV, centeredUV);
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);

    // 1. INPUT PHASE
    float3 raw = float3(0.0, 0.0, 0.0);
    if (u.flags & FLAG_ABERRATION) {
        raw = get_aberration(frame0, s, uv, sqDist);
    } else {
        float4 base = frame0.sample(s, uv);
        raw = float3(base.r, base.g, base.b);
    }

    // 2. GHOSTING PHASE
    float3 proc = float3(raw.r, raw.g, raw.b);
    if (u.flags & FLAG_GHOSTING) {
        float pWeight = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.72;
        float3 f1 = frame1.sample(s, uv).rgb;
        float3 f2 = frame2.sample(s, uv).rgb;
        float3 f3 = frame3.sample(s, uv).rgb;
        float3 f4 = frame4.sample(s, uv).rgb;
        proc = apply_ghosting(raw, f1, f2, f3, f4, pWeight);
    }

    // 3. COLOR & HARDWARE ARTIFACTS
    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03, 0.10, 0.75, 0.15, 0.08, 0.10, 0.82);
    float3 sCol = (proc * gbcMat) * u.colorBoost * 1.44;
    
    if (u.flags & FLAG_BLEED) {
        float4 bleedSample = frame0.sample(s, float2(uv.x, 0.5));
        float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
        sCol -= float3(bleedVal * 0.008, bleedVal * 0.008, bleedVal * 0.008);
        float h = pcg_hash_gbc(floor(uv * gbcRes) * 3.3);
        sCol *= (0.97 + h * 0.06);
    }

    // 4. PHYSICAL SUBSTRATE PHASE
    float maskG = 1.0;
    float maskS = 1.0;

    if (u.flags & FLAG_GRID) {
        float lum = dot(proc, float3(0.299, 0.587, 0.114));
        float thick = mix(0.32, 0.12, lum);
        float2 pCoord = uv * gbcRes;
        float2 unitF = fwidth(pCoord);
        
        float2 grid = abs(fract(pCoord) - 0.5);
maskG = smoothstep(thick, thick - unitF.x * 1.5, grid.x) * smoothstep(thick, thick - unitF.x * 1.5, grid.y);
                   
        float2 sOffset = normalize(centeredUV) * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);
        float2 sGrid = abs(fract(pCoord + sOffset) - 0.5);
        maskS = smoothstep(thick, thick - unitF.x * 1.5, sGrid.x) * smoothstep(thick, thick - unitF.x * 1.5, sGrid.y);
    }

    const float3 pCol = float3(0.20, 0.21, 0.18);
    float3 bg = mix(pCol * 0.5, pCol, maskS) + (sCol * 0.05);
    
    float gridFactor = maskG * u.dotOpacity + (1.0 - u.dotOpacity);
    float3 final = mix(bg, sCol, gridFactor);

    // 5. POWER LED & NEWTON'S RINGS
    if (u.flags & FLAG_NEWTON_RINGS) {
        float rDist = distance(uv, float2(1.1, -0.1));
        float3 rbw = pow(saturate(float3(sin(rDist*18.0), sin(rDist*18.0+2.0), sin(rDist*18.0+4.0))*0.5+0.5), 2.0)*0.045;
        final = final + rbw;
        
        // Power LED effect
        float flicker = (pcg_hash_gbc(float2(float(u.frameIndex % 60u) * 0.01)) * 0.1) + 0.9;
        final.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * flicker;
    }

    if (u.flags & FLAG_REFLECTION) {
        float lDist = distance(uv, float2(1.0, 0.0));
        float reflVal = (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, lDist));
        final = final + (float3(0.92, 0.96, 1.0) * reflVal);
    }

    if (u.flags & FLAG_JITTER) {
        float seed = float(u.frameIndex % 60u) * 0.01;
        float jitterNoise = (pcg_hash_gbc(uv * 4000.0 + seed) - 0.5) * 0.015;
        final = final + float3(jitterNoise, jitterNoise, jitterNoise);
    }

    // 6. POLARIZER & GRAIN
    float grain = (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025;
    float polarizer = (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;
    final = final + float3(grain + polarizer);

    float vign = 1.0 - 0.08 * pow(sqDist, 2.0);
    return float4(final * vign, 1.0);
}
