#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

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

vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    float2 positions[4] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
    float2 uvs[4] = {{0, 1}, {1, 1}, {0, 0}, {1, 0}};
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant CRTUniforms &u [[buffer(0)]]) {
  
    // User Configuration Block: Adjust these parameters to customize the CRT effect.
    // inline set defaults if nil or empty or something line that
    // we need to declare them 


    // scanLineIntensity g
    float scanLineIntensity = u.scanlineIntensity > 0 ? u.scanlineIntensity : 0.5; 



    float barrelAmount = u.barrelAmount > 0 ? u.barrelAmount : 0.1;
    float colorBoost = u.colorBoost > 0 ? u.colorBoost : 1.8;
    float bleedAmount = u.bleedAmount > 0 ? u.bleedAmount : 0.7;
    float time = u.time > 0 ? u.time : 0.0;
    float texSizeX = u.texSizeX > 0 ? tu.exSizeX : 320.0;
    float texSizeY = u.texSizeY > 0 ? tu.exSizeY : 240.0;


    // --- [ MASTER CONFIGURATION BLOCK ] ---
    
    // 1. BLEED & DITHER CONTROL (The "Genesis Waterfall" Settings)
    // HORIZONTAL_SMEAR: Controls how far pixels bleed sideways.
    // 1.0 = Default, 2.5 = Blends dithering (Sonic Waterfalls), 3.0+ = Very blurry.
    const float HORIZONTAL_SMEAR = 2.0; 

    // GLOW_DIFFUSION: Controls the soft vertical glow spilling over scanlines.
    // 0.1 = Sharp, 0.3 = Natural, 0.6+ = "Foggy" Dream-like glow.
    const float GLOW_DIFFUSION = 0.3;

    // 2. SCANLINE & BLOOM CONTROL
    // BLOOM_STRENGTH: Controls how fast scanlines vanish in bright areas.
    // 0.0 = Static. 1.0 = Realistic. 2.0+ = Invisible in pure white.
    const float BLOOM_STRENGTH = 2.2; 

    // SCANLINE_DARK_BOOST: How "thick" lines stay in DARK areas.
    // 1.0 = Standard, 1.5 = Deep black gaps in shadows.
    const float SCANLINE_DARK_BOOST = 1.2;

    // 3. SIGNAL & OPTICS (The "Cable Quality")
    // JITTER: Mimics unstable sync pulses (shaking). Set to 0.0 for a "Perfect" signal.
    const float JITTER_FREQ    = 60.0;   // Frequency of the jitter oscillation (in Hz).
    const float JITTER_AMOUNT  = 0.0002; // 0.0001 = Subtle, 0.0005+ = Extreme "Wobbly" look.

    // CHROMA_SHIFT: Mimics lens distortion/color separation at the screen edges.
    const float CHROMA_SHIFT   = 0.0012; // 0.001 = Subtle, 0.003+ = Extreme "Chromatic Aberration". 
    
    // CONVERGENCE: The alignment of the Red, Green, and Blue electron guns.
    const float CONV_FREQ      = 1.0;     // Hz oscillation.
    const float CONV_AMOUNT    = 0.00015; // 0.0001 = Subtle, 0.0005+ = Misaligned guns.

    // 4. TUBE & COLOR CHARACTERISTICS
    // VIGNETTE: Darkens corners to simulate the curve of a glass tube.
    const float VIG_STRENGTH   = 0.45;  // Extension to center. 0.0 = Off, 0.5 = Moderate.
    const float VIG_POWER      = 1.6;   // Falloff curve. Higher = Sharper cutoff.

    // MASK_INTENSITY: The strength of the physical phosphor grid.
    // 1.0 = No Mask. 0.85 = Heavy Arcade/Slot Mask feel.
    const float MASK_INTENSITY = 0.85;

    // WHITE_BALANCE: Neutralizes pink/magenta tints. 
    // Increase the middle (Green) value to "cool down" a pinkish image.
    const float3 WHITE_BALANCE = float3(0.96, 1.04, 0.95);

    // FLICKER_STRENGTH: Simulates 60Hz phosphor decay organic "hum".
    const float FLICKER_STRENGTH = 0.005;

    // --- [ END OF CONFIGURATION ] ---

    constexpr sampler sLinear(filter::linear, address::clamp_to_edge);
    constexpr sampler sNearest(filter::nearest, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float2 texSize = float2(texSizeX, texSizeY);

    // 1. ANALOG SYNC JITTER
    uv.x += sin(in.position.y * 0.1 + time * JITTER_FREQ) * JITTER_AMOUNT;

    // 2. CRT BARREL DISTORTION
    if (barrelAmount > 0.001) {
        float2 centered = uv * 2.0 - 1.0;
        float2 offset = centered * centered;
        centered += centered * (offset.yx * barrelAmount);
        uv = centered * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return float4(0,0,0,1);
    }

    // 3. COMBINED SAMPLING (The "Green Anchor" Strategy)
    // Nearest-neighbor for Green keeps text sharp; Linear for Red/Blue allows for bloom.
    float dist = length(in.texCoord * 2.0 - 1.0);
    float shift = CHROMA_SHIFT * dist; 
    float conv = CONV_AMOUNT * sin(time * CONV_FREQ);

    float4 color;
    color.g = tex.sample(sNearest, uv).g; 
    color.r = tex.sample(sLinear, uv + float2(shift + conv, conv)).r;
    color.b = tex.sample(sLinear, uv - float2(shift + conv, 0)).b;
    color.a = 1.0;

    // 4. SMART BLEED (Horizontal & Vertical)
    // Horizontal Bleed tuned via HORIZONTAL_SMEAR to blend dithering.
    float dx = 1.0 / texSize.x;
    float3 hBleed = (tex.sample(sLinear, uv - float2(dx * HORIZONTAL_SMEAR, 0)).rgb * 0.3) + 
                    (color.rgb * 0.4) + 
                    (tex.sample(sLinear, uv + float2(dx * HORIZONTAL_SMEAR, 0)).rgb * 0.3);
    color.rgb = mix(color.rgb, hBleed, bleedAmount);

    // Vertical Bleed simulates the vertical "glow" that spills over scanlines.
    float dy = 1.0 / texSize.y;
    float3 vBleed = (tex.sample(sLinear, uv - float2(0, dy * 1.5)).rgb * 0.15) + 
                    (color.rgb * 0.7) + 
                    (tex.sample(sLinear, uv + float2(0, dy * 1.5)).rgb * 0.15);
    color.rgb = mix(color.rgb, vBleed, bleedAmount * GLOW_DIFFUSION);

    // 5. GAMMA & COLOR BALANCING (Gamma-based Color Boost)
    color.rgb = pow(clamp(color.rgb, 0.0, 1.0), float3(1.0 / colorBoost));
    color.rgb *= WHITE_BALANCE;

    // 6. OPTICAL VIGNETTE (Tube corner falloff)
    float2 centeredVig = uv * 2.0 - 1.0;
    color.rgb *= clamp(pow(1.0 - dot(centeredVig * VIG_STRENGTH, centeredVig * VIG_STRENGTH), VIG_POWER), 0.0, 1.0);

    // 7. STAGGERED SLOT MASK (Physical Phosphor Grid)
    {
        int x = int(in.position.x);
        int y = int(in.position.y);
        int m = (x + ((y / 3) % 2 * 2)) % 3;
        float3 mask = (m == 0) ? float3(1.0, MASK_INTENSITY * 1.02, MASK_INTENSITY) : 
                     (m == 1) ? float3(MASK_INTENSITY * 0.98, 1.0, MASK_INTENSITY) : 
                                float3(MASK_INTENSITY, MASK_INTENSITY * 0.98, 1.0);
        color.rgb *= mask;
    }

    // 8. SEPARATED DYNAMIC SCANLINES (Beam Bloom)
    // Bright areas "Bloom" and vanish, dark areas stay thick.
    float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));
    {
        float scanlineControl = sin(uv.y * texSizeY * 3.14159) * 0.5 + 0.5;
        
        // Intensity logic using SCANLINE_DARK_BOOST
        float darkIntensity = scanlineIntensity * mix(1.0, SCANLINE_DARK_BOOST, 1.0 - luma);
        
        // Bloom logic using BLOOM_STRENGTH
        float bloomFactor = clamp(luma * BLOOM_STRENGTH, 0.0, 1.0);
        
        float finalScanline = mix(1.0 - (darkIntensity * scanlineControl), 1.0, bloomFactor);
        color.rgb *= finalScanline;
    }

    // 9. PHOSPHOR FLICKER (Organic 60Hz hum)
    color.rgb *= (sin(time * 60.0) * FLICKER_STRENGTH) + (1.0 - FLICKER_STRENGTH);

    return float4(color.rgb, 1.0);
}