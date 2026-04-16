#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

// --- [ PRE-COMPUTED CONSTANTS ] ---
constant float JITTER_AMOUNT = 0.00015;
constant float V_TRIM = 0.033333;      // 8.0 / 240.0
constant float V_SCALE = 0.933334;     // (1.0 - V_TRIM) - V_TRIM
constant float INV_RES_X = 0.00024414; // 1.0 / 4096.0

// --- [ STRUCTURES ] ---
struct CRTUniforms {
    float scanlineIntensity;
    float barrelAmount;
    float colorBoost;
    float time;
    float bleedAmount;
    float texSizeX;
    float texSizeY;
    float padding;
};

struct ShaderContext {
    float2 centered;
    float distSq; // Using squared distance for performance
};

// --- [ 1. PREPARATION & GEOMETRY ] ---

ShaderContext prepareContext(float2 screenUV, bool soft, bool chroma, bool vig, bool distort) {
    ShaderContext ctx;
    if (soft || chroma || vig || distort) {
        ctx.centered = (screenUV - float2(0.5, 0.52)) * 2.0;
        ctx.centered *= float2(1.06, 1.08);
        ctx.distSq = dot(ctx.centered, ctx.centered); 
    } else {
        ctx.centered = 0; ctx.distSq = 0;
    }
    return ctx;
}

float2 getDistortedUV(float2 screenUV, ShaderContext ctx, float amount, bool active) {
    if (!active) return screenUV;
    float2 offset = ctx.centered * ctx.centered;
    float2 distort = ctx.centered + (ctx.centered * (offset.yx * amount));
    return distort * 0.5 + 0.5;
}

// --- [ 2. COLOR & SAMPLING ] ---

// Optimized: Pass already-sampled colors to avoid re-fetching texture data
float3 applyDitherBleed(float3 rgb, float3 leftColor, float3 rightColor, bool active) {
    if (!active) return rgb;
    float3 bleed = (rgb + leftColor + rightColor) * 0.333;
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    return mix(mix(rgb, bleed, 3.0), rgb, 0.5 + (luma * 0.5));
}

// --- [ 3. ANALOG & SCANLINES ] ---

float3 applyAnalogFinishing(float3 rgb, ShaderContext ctx, float boost, float3 tint, float vStr, float time, float fStr, bool useWhite, bool useVig, bool useFlick) {
    float3 out = rgb * (boost * 1.1);
    if (useWhite) out *= tint;
    if (useVig)   out *= saturate(1.0 - (ctx.distSq * vStr * vStr));
    if (useFlick) out *= (sin(time * 60.0) * fStr) + (1.0 - fStr);
    return out;
}

float3 applyScanlines(float3 rgb, float posY, float baseInt) {
    float scanline = sin(posY * 70.0) * 0.5 + 0.5;
    float scanPow = scanline * scanline * scanline;
    return rgb * (1.0 - baseInt * scanPow);
}

// --- [ 4. FINAL COMPOSITE ] ---

float3 applyMaskAndBezel(float3 rgb, float2 distortUV, float2 sampleUV, texture2d<float> tex, sampler s, float boost, float texX, float rounding, float glowInt, bool bezel) {
    float2 maskEdge = abs(distortUV - 0.5) * 2.0;
    float2 m2 = maskEdge * maskEdge;
    float2 m4 = m2 * m2;
    float2 m8 = m4 * m4;
    float cornerMask = (m8.x * m4.x) + (m8.y * m4.y); 
    
    float tubeVis = 1.0 - smoothstep(1.0, 1.0 + rounding, cornerMask);
    if (distortUV.x < 0.0 || distortUV.x > 1.0 || distortUV.y < 0.0 || distortUV.y > 1.0) tubeVis = 0.0;

    float3 output = rgb * tubeVis;
    if (bezel && tubeVis < 0.99) {
        float bezelW = (1.0 - tubeVis) * (1.0 - smoothstep(1.0, 1.0 + (32.0/texX), max(maskEdge.x, maskEdge.y)));
        if (bezelW > 0.001) {
            float2 mirUV = 1.0 - abs(1.0 - abs(sampleUV)); 
            output += tex.sample(s, mix(mirUV, sampleUV, 0.08)).rgb * boost * bezelW * glowInt;
        }
    }
    return output;
}

// --- [ VERTEX ] ---

vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    const float2 positions[4] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
    const float2 uvs[4] = {{0, 1}, {1, 1}, {0, 0}, {1, 0}};
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

// --- [ RESTORED SCANLINES WITH BLOOM ] ---

float3 applyScanlines(float3 rgb, float3 sourceColor, float posY, float baseInt, float bloomStr, bool useBloom) {
    float scanline = sin(posY * 70.0) * 0.5 + 0.5;
    float intensity = baseInt;
    
    if (useBloom) {
        // Use the luma of the color we already sampled
        float luma = dot(sourceColor, float3(0.2126, 0.7152, 0.0722));
        intensity = mix(baseInt, 0.0, saturate(luma * bloomStr));
    }
    
    float scanPow = scanline * scanline * scanline;
    return rgb * mix(1.0, 1.0 - intensity, scanPow);
}

// --- [ MAIN FRAGMENT ] ---

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant CRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // Flags
    const bool DISTORT = true, SCAN = true, BLEED = true, SOFT = true, CHROMA = true;
    const bool WHITE = true, VIG = true, FLICK = true, BEZEL = true, BLOOM = true;

    // 1. Preparation
    ShaderContext ctx = prepareContext(in.texCoord, SOFT, CHROMA, VIG, DISTORT);

    // 2. Geometry & Coordinates
    float2 distortedUV = getDistortedUV(in.texCoord, ctx, u.barrelAmount, DISTORT);
    float2 sampleUV = distortedUV;
    sampleUV.y = distortedUV.y * V_SCALE + V_TRIM;
    
    float jitter = sin(in.position.y * 0.1 + u.time * 60.0) * JITTER_AMOUNT;
    sampleUV.x += floor(jitter * 4096.0) * INV_RES_X;

    
    // 3. Batched Texture Sampling (Fetch Grouping)
    // We sample all neighbors here to maximize memory bandwidth utilization
    float3 mainColor = tex.sample(s, sampleUV).rgb;
    

    // Chroma/Soft offset calculation
    float blurAmt = SOFT ? (ctx.distSq * ctx.distSq) * 0.0008 : 0.0;
    float pShift = floor((0.0012 * ctx.distSq) * 4096.0) * INV_RES_X;
    
    // Neighbor fetches for Bleed/Chroma
    float spread = 1.0 / u.texSizeX;
    float3 colL = tex.sample(s, sampleUV - float2(spread, 0)).rgb;
    float3 colR = tex.sample(s, sampleUV + float2(spread, 0)).rgb;
    
    float3 rgb = mainColor;

    // 4. Processing Chain (ALU Math)
    if (SOFT) rgb.g = (rgb.g + tex.sample(s, sampleUV + float2(blurAmt)).g) * 0.5;
    if (CHROMA) {
        rgb.r = tex.sample(s, sampleUV + float2(pShift, 0)).r;
        rgb.b = tex.sample(s, sampleUV - float2(pShift, 0)).b;
    }

    rgb = applyDitherBleed(rgb, colL, colR, BLEED);
    rgb = applyAnalogFinishing(rgb, ctx, u.colorBoost, float3(0.96, 1.04, 0.95), 0.45, u.time, 0.005, WHITE, VIG, FLICK);

    // BLOOM
    const float BLOOM_STRENGTH = 1.3;

    if (SCAN) rgb = applyScanlines(rgb, mainColor, in.position.y, u.scanlineIntensity, BLOOM_STRENGTH, BLOOM);
    rgb *= mix(1.0, 1.0, smoothstep(0.0, 1.0, sin(in.position.x * 3.14159)));

    // 5. Final Composite
    float3 finalOut = applyMaskAndBezel(rgb, distortedUV, sampleUV, tex, s, u.colorBoost, u.texSizeX, 0.04, 0.35, BEZEL);

    return float4(saturate(finalOut), 1.0);
}