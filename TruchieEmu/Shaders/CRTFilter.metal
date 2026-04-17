#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

/**
 * CRT EMULATION SHADER
 * -------------------
 * This shader simulates the physical characteristics of a Cathode Ray Tube monitor.
 * It handles geometry warping, color artifacts, and phosphor-level lighting effects.
 */

// --- [ PRE-COMPUTED CONSTANTS ] ---

// JITTER_AMOUNT: Small horizontal "shiver" typical of analog signals.
// Range: 0.0 (still) to 0.001 (noticeable shake). 0.00015 is subtle.
constant float JITTER_AMOUNT = 0.00015;

// V_TRIM & V_SCALE: Adjusts the vertical "Overscan." 
// CRTs often cut off the top/bottom 5-10% of the signal.
constant float V_TRIM = 0.033333;      
constant float V_SCALE = 0.933334;     

// INV_RES_X: Reciprocal of the target texture width (4096px). 
// Used to ensure jitter/chroma offsets align with pixel boundaries.
constant float INV_RES_X = 0.00024414; 

// --- [ STRUCTURES ] ---

struct CRTUniforms {
    float scanlineIntensity; // Darkness of the black horizontal gaps.
    float barrelAmount;      // Strength of the lens/tube curvature.
    float colorBoost;        // Master brightness multiplier.
    float time;              // Drives animation (flicker/jitter).
    float bleedAmount;       // Horizontal color smearing.
    float texSizeX;          // Width of the source texture.
    float texSizeY;          // Height of the source texture.
    float padding;
};

struct ShaderContext {
    float2 centered; // UVs centered at (0,0) for radial math.
    float distSq;   // Squared distance from center (cheap for vignette/softness).
};

// --- [ 1. PREPARATION & GEOMETRY ] ---

/**
 * prepareContext: Sets up the coordinate system for radial effects.
 * Centered at (0.5, 0.52) to give a slight "bottom-heavy" weight common in TV tubes.
 */
ShaderContext prepareContext(float2 screenUV, bool soft, bool chroma, bool vig, bool distort) {
    ShaderContext ctx;
    if (soft || chroma || vig || distort) {
        ctx.centered = (screenUV - float2(0.5, 0.52)) * 2.0;
        ctx.centered *= float2(1.06, 1.08); // Slight zoom to hide raw edges.
        ctx.distSq = dot(ctx.centered, ctx.centered); 
    } else {
        ctx.centered = 0; ctx.distSq = 0;
    }
    return ctx;
}

/**
 * getDistortedUV: Applies "Barrel Distortion."
 * Variables: 
 * - amount: 0.0 (Flat) | 0.15 (Standard) | 0.35 (Fish-eye).
 */
float2 getDistortedUV(float2 screenUV, ShaderContext ctx, float amount, bool active) {
    if (!active) return screenUV;
    float2 offset = ctx.centered * ctx.centered;
    // Warps the coordinates based on their distance from the center.
    float2 distort = ctx.centered + (ctx.centered * (offset.yx * amount));
    return distort * 0.5 + 0.5;
}

// --- [ 2. COLOR & SAMPLING ] ---

/**
 * applyDitherBleed: Simulates low-bandwidth signals where colors smear horizontally.
 * This makes harsh pixel art look more like a continuous analog image.
 */
float3 applyDitherBleed(float3 rgb, float3 leftColor, float3 rightColor, bool active) {
    if (!active) return rgb;
    float3 bleed = (rgb + leftColor + rightColor) * 0.3;//;33;
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    // Bleed is stronger in darker areas and reduced in highlights for clarity.
    return mix(mix(rgb, bleed, 2.0), rgb, 0.5 + (luma * 0.5));
}

// --- [ 3. ANALOG & FINISHING ] ---

/**
 * applyAnalogFinishing: Adds final "vibe" layers.
 * - boost: Brighness multiplier (Standard 1.0 - 1.2).
 * - tint: Greenish-white shift (float3(0.96, 1.04, 0.95)).
 * - vStr (Vignette): 0.1 (Subtle) to 0.7 (Deep shadows in corners).
 * - fStr (Flicker): 0.005 (Standard) to 0.02 (High/Noticeable).
 */
float3 applyAnalogFinishing(float3 rgb, ShaderContext ctx, float boost, float3 tint, float vStr, float time, float fStr, bool useWhite, bool useVig, bool useFlick) {
    float3 out = rgb * (boost * 1.1);
    if (useWhite) out *= tint;
    if (useVig)   out *= saturate(1.0 - (ctx.distSq * vStr * vStr));
    if (useFlick) out *= (sin(time * 60.0) * fStr) + (1.0 - fStr);
    return out;
}

/**
 * applyScanlines: The signature CRT effect.
 * - baseInt: Darkness. 0.3 (PVM) | 0.5 (Arcade) | 0.8 (Cheap TV).
 * - bloomStr: 1.0 (Static) | 1.5+ (Scanlines fade out in bright white areas).
 */
float3 applyScanlines(float3 rgb, float3 sourceColor, float posY, float baseInt, float bloomStr, bool useBloom) {
    float scanline = sin(posY * 70.0) * 0.5 + 0.5;
    float intensity = baseInt;
    
    if (useBloom) {
        // Bright pixels "expand" the electron beam, making the black scanline thinner.
        float luma = dot(sourceColor, float3(0.2126, 0.7152, 0.0722));
        intensity = mix(baseInt, 0.0, saturate(luma * bloomStr));
    }
    
    float scanPow = scanline * scanline * scanline;
    return rgb * mix(1.0, 1.0 - intensity, scanPow);
}

// --- [ 4. FINAL COMPOSITE ] ---

/**
 * applyMaskAndBezel: Clips the image and adds the "internal glow" of the glass.
 * - rounding: 0.02 (Sharp) to 0.1 (Circular). 0.04 is typical.
 * - glowInt: Reflection intensity of the screen image against the plastic bezel.
 */
float3 applyMaskAndBezel(float3 rgb, float2 distortUV, float2 sampleUV, texture2d<float> tex, sampler s, float boost, float texX, float rounding, float glowInt, bool bezel) {
    float2 maskEdge = abs(distortUV - 0.5) * 2.0;
    float2 m2 = maskEdge * maskEdge;
    float2 m4 = m2 * m2;
    float2 m8 = m4 * m4;
    float cornerMask = (m8.x * m4.x) + (m8.y * m4.y); 
    
    // Mask out the "outside" of the tube.
    float tubeVis = 1.0 - smoothstep(1.0, 1.0 + rounding, cornerMask);
    if (distortUV.x < 0.0 || distortUV.x > 1.0 || distortUV.y < 0.0 || distortUV.y > 1.0) tubeVis = 0.0;

    float3 output = rgb * tubeVis;
    
    // Bezel reflection: Samples the texture with mirrors to fake "light spill" on the frame.
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

// --- [ MAIN FRAGMENT ] ---

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant CRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    /**
     * =================================================================================
     * CRT EMULATION SHADER - FEATURE FLAG DOCUMENTATION
     * =================================================================================
     *
     * [ DISTORT ] - Barrel Distortion
     * Simulates the curved glass of a cathode ray tube. It warps the UV coordinates
     * radially. Without this, the screen looks like a flat LCD.
     *
     * [ SCAN ] - Scanline Effect
     * The core CRT look. Draws horizontal dark gaps between rows of pixels.
     * Simulates the electron beam path on physical phosphors.
     *
     * [ BLEED ] - Horizontal Color Smearing
     * Mimics low-bandwidth analog signals (RF/Composite). It blurs pixels horizontally,
     * which was often used by retro artists to create "transparency" or new colors.
     *
     * [ SOFT ] - Dynamic Corner Softness
     * CRTs often lose focus at the edges because the electron beam has further to 
     * travel. This adds a slight blur that increases with distance from the center.
     *
     * [ CHROMA ] - Chromatic Aberration
     * Simulates misaligned electron guns ("Color Fringing"). Shifts Red and Blue 
     * channels away from each other, especially noticeable at the screen edges.
     *
     * [ WHITE ] - White Balance Tinting
     * Applies a specific color profile to the "white" output. Mimics the chemical 
     * tint of vintage phosphor coatings (usually slightly cool/green).
     *
     * [ VIG ] - Vignette
     * Darkens the corners of the screen. Simulates natural light fall-off and 
     * helps focus the viewer's eye on the center of the gameplay.
     *
     * [ FLICKER ] - Refresh Rate Shimmer
     * Adds a subtle 60Hz brightness oscillation. Makes the image feel "alive" 
     * rather than a static digital frame.
     *
     * [ BEZEL ] - Tube Mask & Glow
     * Calculates the physical edge of the glass tube. Adds rounded corners and 
     * simulates the internal reflection of the screen light against the frame.
     *
     * [ BLOOM ] - Scanline Beam Expansion
     * Makes scanlines react to brightness. In bright areas, the "glow" of the 
     * phosphors fills the black gaps, making the image look much brighter.
     * =================================================================================
     */
    const bool DISTORT = true, SCAN = true, BLEED = true, SOFT = true, CHROMA = true;
    const bool WHITE   = true, VIG  = true, FLICK = true, BEZEL = true, BLOOM  = false;

    // 1. Preparation: Handle math context.
    ShaderContext ctx = prepareContext(in.texCoord, SOFT, CHROMA, VIG, DISTORT);

    // 2. Geometry: Handle warping and jitter.
    float2 distortedUV = getDistortedUV(in.texCoord, ctx, u.barrelAmount, DISTORT);
    float2 sampleUV = distortedUV;
    sampleUV.y = distortedUV.y * V_SCALE + V_TRIM; // Overscan trim.
    
    // Horizontal Jitter (simulates unstable sync).
    float jitter = sin(in.position.y * 0.1 + u.time * 60.0) * JITTER_AMOUNT;
    sampleUV.x += floor(jitter * 4096.0) * INV_RES_X;

    // 3. Batched Texture Sampling.
    float3 mainColor = tex.sample(s, sampleUV).rgb;
    
    // Calculate blur and color fringe offsets based on distance from center.
    float blurAmt = SOFT ? (ctx.distSq * ctx.distSq) * 0.0008 : 0.0;
    float pShift = floor((0.0012 * ctx.distSq) * 4096.0) * INV_RES_X;
    
    // Neighbor samples for Bleed and Chroma effects.
    float spread = 1.0 / u.texSizeX;
    float3 colL = tex.sample(s, sampleUV - float2(spread, 0)).rgb;
    float3 colR = tex.sample(s, sampleUV + float2(spread, 0)).rgb;
    
    float3 rgb = mainColor;

    // 4. Processing Chain.
    // SOFT: Sharp in middle, blurry at edges.
    if (SOFT) rgb.g = (rgb.g + tex.sample(s, sampleUV + float2(blurAmt)).g) * 0.5;
    
    // CHROMA: Color misregistration at edges.
    if (CHROMA) {
        rgb.r = tex.sample(s, sampleUV + float2(pShift, 0)).r;
        rgb.b = tex.sample(s, sampleUV - float2(pShift, 0)).b;
    }

    // BLEED & ANALOG: Dithering, Vignette, and Flicker.
    rgb = applyDitherBleed(rgb, colL, colR, BLEED);
    rgb = applyAnalogFinishing(rgb, ctx, u.colorBoost, float3(0.96, 1.04, 0.95), 0.45, u.time, 0.005, WHITE, VIG, FLICK);

    // SCANLINES: Horizontal darkened lines with adaptive bloom.
    const float BLOOM_STRENGTH = 1.3;
    if (SCAN) rgb = applyScanlines(rgb, mainColor, in.position.y, u.scanlineIntensity, BLOOM_STRENGTH, BLOOM);

    // 5. Final Composite: Add bezel mask and glass glow.
    float3 finalOut = applyMaskAndBezel(rgb, distortedUV, sampleUV, tex, s, u.colorBoost, u.texSizeX, 0.04, 0.35, BEZEL);

    return float4(saturate(finalOut), 1.0);
}