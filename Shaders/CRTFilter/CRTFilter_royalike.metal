#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// This structure is now 48 bytes (3 * 16 bytes), which is perfectly aligned.
struct CRTUniforms {
    float scanlineIntensity; // 4
    float barrelAmount;      // 4
    float colorBoost;        // 4
    float time;              // 4
    float bleedAmount;       // 4
    float texSizeX;          // 4
    float texSizeY;          // 4
    float padding;           // 4 (Total 32)
};


// --- Helper for Horizontal Bleed ---
float4 getBleedingColor(texture2d<float> tex, sampler s, float2 uv, float2 texSize, float bleedAmount) {
    float dx = 1.0 / texSize.x;
    
    // Always sample the center purely to prevent doubling the main image
    float4 center = tex.sample(s, uv);
    
    if (bleedAmount <= 0.0) return center;
    
    // Apply the jitter ONLY to the surrounding taps
    float jitter = sin(uv.y * 500.0) * dx; 
    
    float4 left   = tex.sample(s, uv - float2(dx + jitter, 0));
    float4 right  = tex.sample(s, uv + float2(dx - jitter, 0));
    
    // Mix center (sharp) with the jittery neighbors (bleeding)
    float4 blurred = (center * 0.5) + (left * 0.25) + (right * 0.25);
    return mix(center, blurred, bleedAmount);
}

vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    float2 positions[4] = { {-1, -1}, {1, -1}, {-1, 1}, {1, 1} };
    float2 uvs[4]       = { {0, 1},   {1, 1},  {0, 0},  {1, 0} };
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant CRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float2 uv = in.texCoord;

    // --- CRT barrel distortion ---
    if (u.barrelAmount > 0.001) {
        float2 centered = uv * 2.0 - 1.0;
        float2 offset   = centered * centered;
        centered += centered * (offset.yx * u.barrelAmount);
        uv = centered * 0.5 + 0.5;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0, 0, 0, 1);
        }
    }

    // Ensure texSize is coming from your struct correctly
    float2 texSize = float2(u.texSizeX, u.texSizeY); 

    // Keep the phaseShift logic, but let's make it stronger for your display:
    // We use 'in.position.y' to make it line-specific. 
    // We use '1.5' instead of '0.5' to make the crawl more aggressive.
    float2 phaseShift = float2(sin(in.position.y * 3.14159) * 0.55 * (1.0 / u.texSizeX), 0.0);
    float4 color = getBleedingColor(tex, s, uv + phaseShift, texSize, u.bleedAmount);
    
    // --- 1. Apply Horizontal Bleed first ---
    color.rgb *= u.colorBoost;

    // --- 2. CRT effects (fringing, glow, vignette) ---
    float2 centered = uv * 2.0 - 1.0;
    float vig = 1.0 - dot(centered * 0.4, centered * 0.4);
    vig = clamp(pow(vig, 1.5), 0.0, 1.0);
    
    float shift = 0.002;
    float r = tex.sample(s, uv + float2(shift, 0)).r;
    float b = tex.sample(s, uv - float2(shift, 0)).b;
    color.r = r;
    color.b = b;

    float glow = (color.r + color.g + color.b) / 3.0;
    color.rgb += glow * 0.08;
    color.rgb *= vig;

    // --- 3. Phosphor mask ---
    int m = int(in.position.x) % 3;
    float3 mask = (m == 0) ? float3(1.0, 0.75, 0.75) : 
                  (m == 1) ? float3(0.75, 1.0, 0.75) : 
                             float3(0.75, 0.75, 1.0);
    color.rgb *= mask;

    // --- 4. Scanlines (locked to screen pixels) ---
    // In the scanline section of your shader:
    if (u.scanlineIntensity > 0.001) {
        // Higher multiplier = more lines
        float scanLine = sin(in.position.y * 3.14159 / 4.0) * 0.5 + 0.5;
        // Increase the multiplier (e.g., 0.8) to make them darker
        color.rgb *= (1.2 - (u.scanlineIntensity * scanLine * 0.8));
    }
    
    color.a = 1.0;
    return color;
}