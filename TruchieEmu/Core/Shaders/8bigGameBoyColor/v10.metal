/*
 * TruchieEmu: 8bit Game Boy Color Hardware Simulation (Dandelion Edition)
 * VERSION HISTORY:
 * v22.4: THE OMNI-MERGE
 * - RESTORED: All original v21.0 features (Newton's Rings, Topography, Dust Glints, Shell)
 * - INTEGRATED: Refined Exponential Ghosting
 * - INTEGRATED: DMG-Style Metallic Reflector (Light Position + Interference Waves)
 * - FIXED: drawStringGBC Address Space mismatch
 */

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// --- FEATURE FLAGS ---
#define FLAG_GHOSTING       (1 << 0)
#define FLAG_GRID         (1 << 1)
#define FLAG_ABERRATION   (1 << 2)
#define FLAG_BLEED      (1 << 3)
#define FLAG_NEWTON_RINGS (1 << 4)
#define FLAG_JITTER     (1 << 5)
#define FLAG_REFLECTION  (1 << 6)
#define FLAG_GRAIN      (1 << 7)
#define FLAG_VIGNETTE  (1 << 8)
#define FLAG_TOPOGRAPHY (1 << 9)
#define FLAG_COLOR_MATRIX (1 << 10)

struct GBCUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float physicalDepth;
    float ghostingWeight;
    uint  frameIndex;
    uint  flags;
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float showShell;
    float showStrip;
    float showLens;
    float showText;
    float showLED;
    float lightPositionIndex;
    float lightStrength;
    float shellColorIndex;
    float gridThicknessDark;
    float gridThicknessLight;
    float4 sourceSize;
    float4 outputSize;
};

// --- SIMULATION MODULES ---

float3 apply_ghosting_refinedGBC(float3 f0, float3 f1, float3 f2, float3 f3, float3 f4, float weight) {
    float3 trail = mix(f1, mix(f2, mix(f3, f4, 0.3), 0.4), 0.5);
    return mix(f0, trail, weight);
}

float pcg_hash_gbc(float2 p) {
    uint2 v = uint2(p);
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    return float(v.x) * (1.0 / 4294967296.0);
}

float hardware_gold_noise(float2 p, float seed) {
    return fract(tan(distance(p * 1.61803398875, p) * seed) * (p.x + seed));
}

// Ported Metallic Reflector Logic
float3 applyMetallicReflector(float3 color, float2 p, float2 res, constant GBCUniforms &u) {
    float2 lightPos;
    int idx = int(u.lightPositionIndex);
    if (idx == 0)      lightPos = float2(res.x, 0.0);
    else if (idx == 1) lightPos = float2(0.0, 0.0);
    else if (idx == 2) lightPos = float2(res.x * 0.5, 0.0);
    else if (idx == 3) lightPos = float2(res.x * 0.5, res.y * 0.5);
    else if (idx == 4) lightPos = float2(0.0, res.y * 0.5);
    else if (idx == 5) lightPos = float2(res.x, res.y * 0.5);
    else if (idx == 6) lightPos = float2(0.0, res.y);
    else if (idx == 7) lightPos = float2(res.x * 0.5, res.y);
    else               lightPos = float2(res.x, res.y);

    float distToLight = length(p - lightPos);
    float wave1 = sin(p.x * 5.0 - p.y * 2.5);
    float wave2 = sin(p.x * 2.1 + p.y * 4.8);
    float metallicGrain = (wave1 * wave2) * 0.5 + 0.5;
    float sheen = smoothstep(-res.x * 0.6, res.x * 1.1, p.x - p.y);
    float glare = smoothstep(res.x * 0.8, 0.0, distToLight);
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float reflectionMask = smoothstep(0.05, 0.5, luma); 
    
    return (glare * 0.25 + sheen * 0.10 + metallicGrain * 0.02) * float3(0.9, 0.95, 1.0) * reflectionMask * u.lightStrength;
}

// --- SHELL RENDERING ---

float3 getShellColor(float idx) {
 if (idx < 0.5) return float3(0.55, 0.25, 0.65); // Berry
 if (idx < 1.5) return float3(0.45, 0.30, 0.60); // Grape
 if (idx < 2.5) return float3(0.18, 0.18, 0.20); // Onyx
 if (idx < 3.5) return float3(0.70, 0.85, 0.90); // Glacier
 if (idx < 4.5) return float3(0.95, 0.55, 0.10); // Orange
 if (idx < 5.5) return float3(0.60, 0.25, 0.50); // Dahlia
 if (idx < 6.5) return float3(0.25, 0.70, 0.65); // Teal
 if (idx < 7.5) return float3(0.25, 0.35, 0.70); // Indigo
 return float3(0.55, 0.25, 0.65);
}

uint getCharBlockGBC(int c) {
    switch(c) {
        case 0: return 11245; case 1: return 27566; case 2: return 31015;
        case 3: return 31143; case 4: return 14699; case 5: return 18727;
        case 6: return 24429; case 7: return 15211; case 8: return 27556;
        case 9: return 27565; case 10: return 23421; case 11: return 23186;
        default: return 0;
    }
}

constant int TEXT_GAMEBOY_LOGO[8] = {4,0,6,3, -1, 1,7,11};
constant int TEXT_COLOR_LOGO[5]   = {2,7,5,7,9};

float drawStringGBC(float2 p, constant int* textArray, int len) {
    int charIndex = int(floor(p.x / 4.0));
    if (charIndex < 0 || charIndex >= len) return 0.0;
    float2 charP = float2(fmod(max(p.x, 0.0), 4.0), p.y);
    if (charP.x >= 3.0 || charP.y < 0.0 || charP.y >= 5.0) return 0.0;
    int c = textArray[charIndex];
    if (c == -1) return 0.0;
    uint glyph = getCharBlockGBC(c);
    int bit = 14 - (int(floor(charP.y)) * 3 + int(floor(charP.x)));
    return (glyph & (1u << bit)) != 0 ? 1.0 : 0.0;
}

float sdRoundRectGBC(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + float2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

float4 renderGBCShell(float2 p, constant GBCUniforms &u) {
    float2 screenCenter = float2(0.0, -8.0);
    float2 screenSize = float2(70.0, 52.0);
    float2 lensCenter = float2(0.0, 3.0);
    float2 lensSize = float2(83.0, 72.0);
    float2 lensP = p - lensCenter;
    float lensSDF = sdRoundRectGBC(lensP, lensSize, 10.0);
    
    if (lensP.y > 45.0) {
        float flare = 12.0 * smoothstep(45.0, 72.0, lensP.y);
        float2 flareP = lensP; flareP.x = abs(flareP.x) - flare;
        float flareSDF = sdRoundRectGBC(float2(flareP.x, lensP.y - 65.0), float2(15.0, 8.0), 8.0);
        lensSDF = min(lensSDF, flareSDF);
    }
    
    float screenSDF = sdRoundRectGBC(p - screenCenter, screenSize, 1.0);
    float3 col = getShellColor(u.shellColorIndex);

    if (lensSDF < 0.0 && screenSDF > 0.0) {
        col = float3(0.16, 0.16, 0.18);
        if (screenSDF < 0.6) col = float3(0.04, 0.04, 0.05);
        if (length(p - float2(-78.0, -8.0)) < 2.2) col = float3(1.0, 0.2, 0.1);
        
        float2 logoP = p - float2(-34.0, 52.0);
        if (drawStringGBC(logoP, TEXT_GAMEBOY_LOGO, 8) > 0.5) col = float3(0.65);
        float2 colorP = logoP - float2(36.0, 0.0);
        if (drawStringGBC(colorP, TEXT_COLOR_LOGO, 5) > 0.5) {
            float3 cCols[5] = {float3(0.5,0.2,0.7), float3(0.3,0.8,0.2), float3(0.9,0.8,0.1), float3(0.1,0.4,0.9), float3(0.9,0.1,0.2)};
            col = cCols[clamp(int(floor(colorP.x/4.0)), 0, 4)];
        }
    }
    return float4(col, 1.0);
}

// --- MAIN FRAGMENT SHADER ---

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> frame0 [[texture(0)]],
                                texture2d<float> frame1 [[texture(1)]],
                                texture2d<float> frame2 [[texture(2)]],
                                texture2d<float> frame3 [[texture(3)]],
                                texture2d<float> frame4 [[texture(4)]],
                                constant GBCUniforms &u [[buffer(0)]]) {
    
    if (u.showShell > 0.5) {
        float scale = min(u.outputSize.x / 165.0, u.outputSize.y / 155.0);
        float2 p = (in.position.xy - (u.outputSize.xy * 0.5)) / scale;
        float2 screenCenter = float2(0.0, -8.0);
        float2 screenSize = float2(70.0, 52.0);
        float screenSDF = sdRoundRectGBC(p - screenCenter, screenSize, 1.0);

        if (screenSDF < 0.0) {
            constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);
            float2 uv = (p - (screenCenter - screenSize)) / (screenSize * 2.0);
            float2 centeredUV = uv - float2(0.5, 0.5);
            float sqDist = dot(centeredUV, centeredUV);

            float3 f0 = frame0.sample(samp, uv).rgb;
            if (u.flags & FLAG_ABERRATION) {
                float abOffset = 0.0006 * sqDist;
                f0.r = frame0.sample(samp, uv + float2(abOffset, 0.0)).r;
                f0.b = frame0.sample(samp, uv - float2(abOffset, 0.0)).b;
            }

            float3 color = f0;
            if (u.flags & FLAG_GHOSTING) {
                float3 f1 = frame1.sample(samp, uv).rgb;
                float3 f2 = frame2.sample(samp, uv).rgb;
                float3 f3 = frame3.sample(samp, uv).rgb;
                float3 f4 = frame4.sample(samp, uv).rgb;
                color = apply_ghosting_refinedGBC(f0, f1, f2, f3, f4, u.ghostingWeight);
            }

            float2 gbcRes = u.sourceSize.xy;
            float2 pCoord = uv * gbcRes;
            float2 pixelIndex = floor(uv * gbcRes);
            float topoShimmer = 0.0;

            if (u.flags & FLAG_TOPOGRAPHY) {
                float2 cellUV = fract(pCoord + hardware_gold_noise(pixelIndex, 12.12) * 0.005);
                float2 pNormal = (cellUV - 0.5) * 2.0;
                float wellDepth = saturate(1.0 - length(pNormal * 1.1));
                topoShimmer = pow(wellDepth, 0.5);
                color *= (0.85 + topoShimmer * 0.15);
            }

            color += applyMetallicReflector(color, pCoord, gbcRes, u);

            if (u.flags & FLAG_BLEED) {
                float4 bleedSample = frame0.sample(samp, float2(uv.x, 0.5));
                float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
                color -= float3(bleedVal * 0.008);
                float h = pcg_hash_gbc(pixelIndex * 3.3);
                color *= (0.97 + h * 0.06);
            }

            float2 grid = abs(fract(uv * u.sourceSize.xy - 0.5) - 0.5) / fwidth(uv * u.sourceSize.xy);
            color *= mix(1.0, 0.85, (1.0 - smoothstep(0.0, 1.0, min(grid.x, grid.y)))) * u.dotOpacity;

            float shadow = smoothstep(-52.0, -47.0, p.y - screenCenter.y) * smoothstep(70.0, 65.0, p.x - screenCenter.x);
            if (u.flags & FLAG_COLOR_MATRIX) color = color * float3x3(0.85, 0.1, 0.05, 0.05, 0.85, 0.1, 0.1, 0.05, 0.85);

            if (u.flags & FLAG_REFLECTION) {
                float reflVal = (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, length(uv - float2(1.0, 0.0)))) * 0.2;
                color += (float3(0.92, 0.96, 1.0) * reflVal);
                float sheen = pow(saturate(uv.x + (1.0 - uv.y) - 0.8), 3.0) * (u.specularShininess * 0.09) * 0.2;
                color += (float3(0.92, 0.95, 1.0) * sheen * (0.8 + topoShimmer * 0.2));
                color += (float3(1.0) * pow(pcg_hash_gbc(uv * 4000.0 + 1.0), 30.0) * sheen * 0.2);
            }

            if (u.flags & FLAG_NEWTON_RINGS) {
                float rDist = distance(uv, float2(1.1, -0.1));
                color += pow(saturate(float3(sin(rDist*18.0), sin(rDist*18.0+2.0), sin(rDist*18.0+4.0))*0.5+0.5), 2.0)*0.045;
                float flicker = (pcg_hash_gbc(float2(float(u.frameIndex % 60u) * 0.01)) * 0.1) + 0.9;
                color.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * flicker;
            }

            if (u.flags & FLAG_JITTER) color += (pcg_hash_gbc(uv * 4000.0 + float(u.frameIndex % 60u) * 0.01) - 0.5) * 0.015;
            if (u.flags & FLAG_GRAIN) color += (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025 + (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;
            if (u.flags & FLAG_VIGNETTE) color *= (1.0 - 0.08 * pow(sqDist, 2.0));

            return float4(color * mix(0.74, 1.0, shadow) * u.brightnessBoost, 1.0);
        }
        return renderGBCShell(p, u);
    }

    // --- CORE EFFECT PIPELINE ---
    const float2 gbcRes = u.sourceSize.xy;
    float2 uv = in.texCoord;
    float2 centeredUV = uv - float2(0.5, 0.5);
    float sqDist = dot(centeredUV, centeredUV);
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);

    float3 f0 = frame0.sample(s, uv).rgb;
    if (u.flags & FLAG_ABERRATION) {
        float abOffset = 0.0006 * sqDist;
        f0.r = frame0.sample(s, uv + float2(abOffset, 0.0)).r;
        f0.b = frame0.sample(s, uv - float2(abOffset, 0.0)).b;
    }

    float3 proc = f0;
    if (u.flags & FLAG_GHOSTING) {
        float pWeight = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.72;
        float3 f1 = frame1.sample(s, uv).rgb;
        float3 f2 = frame2.sample(s, uv).rgb;
        float3 f3 = frame3.sample(s, uv).rgb;
        float3 f4 = frame4.sample(s, uv).rgb;
        proc = apply_ghosting_refinedGBC(f0, f1, f2, f3, f4, pWeight);
    }

    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03, 0.10, 0.75, 0.15, 0.08, 0.10, 0.82);
    float3 sCol = (u.flags & FLAG_COLOR_MATRIX) ? (proc * gbcMat) * u.colorBoost * 1.44 : proc * u.colorBoost;
    
    float2 pCoord = uv * gbcRes;
    float2 pixelIndex = floor(uv * gbcRes);
    float topoShimmer = 0.0;
    
    if (u.flags & FLAG_TOPOGRAPHY) {
        float2 cellUV = fract(pCoord + hardware_gold_noise(pixelIndex, 12.12) * 0.005);
        float2 pNormal = (cellUV - 0.5) * 2.0;
        float wellDepth = saturate(1.0 - length(pNormal * 1.1));
        topoShimmer = pow(wellDepth, 0.5);
        sCol *= (0.85 + topoShimmer * 0.15);
    }

    sCol += applyMetallicReflector(sCol, pCoord, gbcRes, u);
    
    if (u.flags & FLAG_BLEED) {
        float4 bleedSample = frame0.sample(s, float2(uv.x, 0.5));
        float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
        sCol -= float3(bleedVal * 0.008);
        sCol *= (0.97 + pcg_hash_gbc(pixelIndex * 3.3) * 0.06);
    }

    float maskG = 1.0; float maskS = 1.0;
    if (u.flags & FLAG_GRID) {
        float thick = mix(1.0 - (u.gridThicknessDark > 0.0 ? u.gridThicknessDark : 0.2), 1.0 - (u.gridThicknessLight > 0.0 ? u.gridThicknessLight : 0.1), dot(proc, float3(0.299, 0.587, 0.114)));
        maskG = smoothstep(thick, 0.0, abs(fract(pCoord) - 0.5).x) * smoothstep(thick, 0.0, abs(fract(pCoord) - 0.5).y);
        float2 sOffset = normalize(centeredUV) * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);
        maskS = smoothstep(thick, 0.0, abs(fract(pCoord + sOffset) - 0.5).x) * smoothstep(thick, 0.0, abs(fract(pCoord + sOffset) - 0.5).y);
    }

    float3 bg = mix(float3(0.10, 0.10, 0.09), float3(0.20, 0.21, 0.18), maskS) + (sCol * 0.05);
    float3 final = mix(bg, sCol, maskG * u.dotOpacity + (1.0 - u.dotOpacity)) * 0.65;

    if (u.flags & FLAG_NEWTON_RINGS) {
        float rDist = distance(uv, float2(1.1, -0.1));
        final += pow(saturate(float3(sin(rDist*18.0), sin(rDist*18.0+2.0), sin(rDist*18.0+4.0))*0.5+0.5), 2.0)*0.045;
        final.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * ((pcg_hash_gbc(float2(float(u.frameIndex % 60u) * 0.01)) * 0.1) + 0.9);
    }

    if (u.flags & FLAG_REFLECTION) {
        float sheen = pow(saturate(uv.x + (1.0 - uv.y) - 0.8), 3.0) * (u.specularShininess * 0.09) * 0.2;
        final += (float3(0.92, 0.96, 1.0) * (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, length(uv - float2(1.0, 0.0)))) * 0.2);
        final += (float3(0.92, 0.95, 1.0) * sheen * (0.8 + topoShimmer * 0.2));
        final += (float3(1.0) * pow(pcg_hash_gbc(uv * 4000.0 + 1.0), 30.0) * sheen * 0.2);
    }

    if (u.flags & FLAG_JITTER) final += (pcg_hash_gbc(uv * 4000.0 + float(u.frameIndex % 60u) * 0.01) - 0.5) * 0.015;
    if (u.flags & FLAG_GRAIN) final += (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025 + (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;
    
    float vign = (u.flags & FLAG_VIGNETTE) ? 1.0 - 0.08 * pow(sqDist, 2.0) : 1.0;
    return float4(final * vign * u.brightnessBoost, 1.0);
}