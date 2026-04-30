/*
 * TruchiEmu: 8bit Game Boy Color Hardware Simulation
 * VERSION HISTORY:
 * v17.9: Hybrid Elite + Final Elite Features
 * - Added topography/well effect
 * - Added cool blue sheen
 * - Added dust glints
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

float hardware_gold_noise(float2 p, float seed) {
    return fract(tan(distance(p * 1.61803398875, p) * seed) * (p.x + seed));
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

    // 3. COLOR & TOPOGRAPHY
    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03, 0.10, 0.75, 0.15, 0.08, 0.10, 0.82);
    float3 sCol = (proc * gbcMat) * u.colorBoost * 1.44;
    
    // Topography/well effect
    float2 pCoord = uv * gbcRes;
    float2 pixelIndex = floor(uv * gbcRes);
    float2 cellUV = fract(pCoord + hardware_gold_noise(pixelIndex, 12.12) * 0.005);
    float2 pNormal = (cellUV - 0.5) * 2.0;
    float wellDepth = saturate(1.0 - length(pNormal * 1.1));
    float topoShimmer = pow(wellDepth, 0.5);
    sCol *= (0.85 + topoShimmer * 0.15);
    
    if (u.flags & FLAG_BLEED) {
        float4 bleedSample = frame0.sample(s, float2(uv.x, 0.5));
        float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
        sCol -= float3(bleedVal * 0.008, bleedVal * 0.008, bleedVal * 0.008);
        float h = pcg_hash_gbc(pixelIndex * 3.3);
        sCol *= (0.97 + h * 0.06);
    }

    // 4. PHYSICAL SUBSTRATE PHASE
    float maskG = 1.0;
    float maskS = 1.0;

    if (u.flags & FLAG_GRID) {
        // =========================================================================
        // GRID CONTROLS - Tune these values to adjust pixel separation
        // =========================================================================
        // Grid thickness input for dark pixels (user-friendly: 0.1 = thin, 0.5 = medium, 0.9 = thick)
        // Range: 0.0 to 1.0 (CODE inverts: 0.1 becomes 0.9 internally)
        constexpr float kGridThicknessDark = 0.2;
        // Grid thickness input for light pixels (user-friendly: 0.1 = thin, 0.5 = medium, 0.9 = thick)
        // Range: 0.0 to 1.0 (CODE inverts: 0.1 becomes 0.9 internally)
        constexpr float kGridThicknessLight = 0.1;
        // =========================================================================
        
        float lum = dot(proc, float3(0.299, 0.587, 0.114));
        float thick = mix(1.0 - kGridThicknessDark, 1.0 - kGridThicknessLight, lum);
        // Reuse pCoord from above
        float2 unitF = fwidth(pCoord);
        
        float2 grid = abs(fract(pCoord) - 0.5);
maskG = smoothstep(thick, 0.0, grid.x) * smoothstep(thick, 0.0, grid.y);
                   
        float2 sOffset = normalize(centeredUV) * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);
        float2 sGrid = abs(fract(pCoord + sOffset) - 0.5);
        maskS = smoothstep(thick, 0.0, sGrid.x) * smoothstep(thick, 0.0, sGrid.y);
    }

    const float3 pCol = float3(0.20, 0.21, 0.18);
    float3 bg = mix(pCol * 0.5, pCol, maskS) + (sCol * 0.05);
    
    // Apply grid mask
    float gridFactor = maskG * u.dotOpacity + (1.0 - u.dotOpacity);
    float3 final = mix(bg, sCol, gridFactor) * 0.65;

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
        // =========================================================================
        // REFLECTION CONTROLS - Tune these values to adjust reflection intensity
        // =========================================================================
        // Base reflection from top-right light source (0.0 = off, 1.0 = full)
        constexpr float kReflectionIntensity = 0.2;
        // Cool blue glass sheen overlay (0.0 = off, 1.0 = full)
        constexpr float kSheenIntensity = 0.2;
        // Random dust sparkle particles (0.0 = off, 1.0 = full)
        constexpr float kDustGlintIntensity = 0.2;
        // =========================================================================
        
        float lDist = distance(uv, float2(1.0, 0.0));
        
        // REFLECTION: Top-right specular highlight
        float reflVal = (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, lDist)) * kReflectionIntensity;
        final = final + (float3(0.92, 0.96, 1.0) * reflVal);
        
        // SHEEN: Cool blue gradient sheen from top-right corner
        float linearGrad = saturate(uv.x + (1.0 - uv.y) - 0.8);
        float sheenStrength = pow(linearGrad, 3.0) * (u.specularShininess * 0.09) * kSheenIntensity;
        float3 sheen = float3(0.92, 0.95, 1.0) * sheenStrength * (0.8 + topoShimmer * 0.2);
        final = final + sheen;
        
        // DUST GLINTS: Random sparkle particles on screen surface
        float dustNoise = pcg_hash_gbc(uv * 4000.0 + 1.0);
        float3 glints = float3(1.0) * pow(dustNoise, 30.0) * sheenStrength * kDustGlintIntensity;
        final = final + glints;
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
