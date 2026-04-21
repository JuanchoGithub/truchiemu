#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex shader (shared by all shaders in the default library)
vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    float2 positions[4] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
    float2 uvs[4]       = {{0, 1},   {1, 1},  {0, 0},  {1, 0}};
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

// MARK: - Enhanced CRT + Scanline fragment shader with uniforms
struct CRTUniforms {
    float scanlineIntensity;  // 0.0 - 1.0: scanline strength (0 = off)
    float barrelAmount;       // 0.0 - 0.5: barrel distortion (0 = off)
    float colorBoost;         // 0.5 - 2.0: brightness multiplier
    float time;               // Frame time for animated effects
    float flickerAmount;      // 0.0 - 0.1: phosphor flicker intensity
};

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant CRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;

    // 1. Analog Sync Jitter (Calculated BEFORE sampling)
    // Moves the actual texture coordinates slightly over time
    float jitter = sin(in.position.y * 0.1 + u.time * 60.0) * 0.0003;
    uv.x += jitter;

    // 2. Barrel Distortion
    if (u.barrelAmount > 0.001) {
        float2 centered = uv * 2.0 - 1.0;
        float2 offset   = centered * centered;
        centered += centered * (offset.yx * u.barrelAmount);
        uv = centered * 0.5 + 0.5;

        // Cutoff for the "rounded" tube edges
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0, 0, 0, 1);
        }
    }

    // 3. Non-Linear Chromatic Aberration
    // Aberration increases towards the edges of the "lens"
    float distFromCenter = length(in.texCoord * 2.0 - 1.0);
    float shift = 0.0015 * distFromCenter; 
    float r = tex.sample(s, uv + float2(shift, 0)).r;
    float g = tex.sample(s, uv).g;
    float b = tex.sample(s, uv - float2(shift, 0)).b;
    float4 color = float4(r, g, b, 1.0);

    // 4. Gamma-based Color Boost
    color.rgb = pow(color.rgb, float3(1.0 / u.colorBoost));

    // 5. CRT Vignette & Curvature
    float2 centered = uv * 2.0 - 1.0;
    float vig = 1.0 - dot(centered * 0.4, centered * 0.4);
    vig = clamp(pow(vig, 1.5), 0.0, 1.0);
    
    float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb += luma * 0.05; // Phosphor bleed
    color.rgb *= vig;

    // 6. Staggered Slot Mask (Arcade Style)
    {
        int x = int(in.position.x);
        int y = int(in.position.y);
        int y_offset = (y / 3) % 2; 
        int m = (x + (y_offset * 2)) % 3;
        float3 mask = (m == 0) ? float3(1.0, 0.8, 0.8) : (m == 1 ? float3(0.8, 1.0, 0.8) : float3(0.8, 0.8, 1.0));
        color.rgb *= mask;
    }

    // 7. Dynamic Scanlines (Corrected mix logic)
    {
        float scanlineControl = sin(uv.y * 800.0) * 0.5 + 0.5;
        // Beam Bloom: Scanlines are lighter where the image is brighter
        float intensity = u.scanlineIntensity * (1.1 - luma);
        float scanlineVal = 1.0 - (intensity * scanlineControl);
        color.rgb *= mix(scanlineVal, 1.0, luma * 0.4); 
    }

    // 8. Phosphor Flicker
    if (u.flickerAmount > 0.001) {
        float flicker = sin(u.time * 60.0) * 0.02 + 0.98;
        color.rgb *= mix(1.0, flicker, u.flickerAmount);
    }

    return float4(color.rgb, 1.0);
}