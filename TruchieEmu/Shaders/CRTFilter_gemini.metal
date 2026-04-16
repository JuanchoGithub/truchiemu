#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex shader
vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    float2 positions[4] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
    float2 uvs[4] = {{0, 1}, {1, 1}, {0, 0}, {1, 0}};
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

// MARK: - Hardcoded CRT Fragment Shader
fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]]) {
    
    // --- SET YOUR PREFERENCES HERE ---
    const float scanlineIntensity = 0.5; // 0.0 to 1.0
    const float barrelAmount      = 0.15; // 0.0 to 0.5
    const float colorBoost        = 1.2;  // 1.0 to 2.0 (Gamma)
    // ---------------------------------

    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;

    // 1. Barrel Distortion
    if (barrelAmount > 0.001) {
        float2 centered = uv * 2.0 - 1.0;
        float2 offset = centered * centered;
        centered += centered * (offset.yx * barrelAmount);
        uv = centered * 0.5 + 0.5;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0, 0, 0, 1);
        }
    }

    // 2. True Chromatic Aberration (3-Tap)
    float shift = 0.0015; 
    float r = tex.sample(s, uv + float2(shift, 0)).r;
    float g = tex.sample(s, uv).g;
    float b = tex.sample(s, uv - float2(shift, 0)).b;
    float4 color = float4(r, g, b, 1.0);

    // 3. Gamma-based Color Boost
    color.rgb = pow(color.rgb, float3(1.0 / colorBoost));

    // 4. CRT Vignette & Phosphor Glow
    float2 centered = uv * 2.0 - 1.0;
    float vig = 1.0 - dot(centered * 0.45, centered * 0.45);
    vig = clamp(pow(vig, 1.6), 0.0, 1.0);
    
    float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb += luma * 0.05; // Subtle phosphor bleed
    color.rgb *= vig;

    // 5. Staggered Slot Mask
    {
        float3 mask = float3(1.0);
        int x = int(in.position.x);
        int y = int(in.position.y);
        int y_offset = (y / 3) % 2; 
        int m = (x + (y_offset * 2)) % 3;
        
        if (m == 0)      mask = float3(1.0, 0.75, 0.75);
        else if (m == 1) mask = float3(0.75, 1.0, 0.75);
        else             mask = float3(0.75, 0.75, 1.0);
        
        color.rgb *= mask;
    }

    // 6. Dynamic Scanlines
    {
        float dynamicIntensity = scanlineIntensity * (1.1 - luma);
        float scanLine = sin(uv.y * 800.0) * 0.5 + 0.5;
        color.rgb *= 1.0 - (dynamicIntensity * scanLine);
    }

    return float4(color.rgb, 1.0);
}